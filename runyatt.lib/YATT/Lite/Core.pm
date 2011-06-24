package YATT::Lite::Core; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use Carp;
use base qw(YATT::Lite::VFS);
use fields qw(cf_namespace cf_debug_cgen cf_no_lineinfo cf_check_lineno
	      cf_tmpl_encoding
	      cf_debug_parser
	      cf_parse_while_loading cf_only_parse
	      cf_die_in_error cf_error_handler
	      cf_special_entities

	      cgen_class
	    );
use YATT::Lite::Util;
use YATT::Lite::Constants;
use YATT::Lite::Entities qw(build_entns);

# XXX: YATT::Lite に？
use YATT::Lite::Breakpoint ();

#========================================
# 以下、 package YATT::Lite のための、内部クラス
#========================================
{
  use YATT::Lite::VFS qw(Folder Item);
  use YATT::Lite::Types
    ([Part => -base => MY->Item
      , -fields => [qw(toks arg_dict arg_order
		       cf_namespace cf_kind cf_folder cf_data
		       cf_implicit cf_suppressed
		       cf_startln cf_bodyln cf_endln
		       cf_startpos cf_bodypos cf_bodylen
		     )]
      , -constants => [[public => 0]]
      , [Widget => -fields => [qw(tree var_dict has_required_arg)]
	 , [Page => (), -constants => [[public => 1]]]]
      , [Action => (), -constants => [[public => 1]]]
      , [Data => ()]]

     , [Template => -base => MY->File
	, -alias => 'vfs_file'
	, -fields => [qw(product parse_ok cf_mtime cf_utf8 cf_age
			 cf_usage cf_constants
			 cf_ignore_trailing_newlines
		       )]]
    );

  # folder の weaken は parser がしてる。
#  sub YATT::Lite::Core::Part::source {
#    (my Part $part) = @_;
#    join "", map {ref $_ ? "\n" x $$_[0] : $_} @{$part->{source}};
#  }
  sub YATT::Lite::Core::Template::source_length {
    (my Template $self) = @_;
    length $self->{cf_string};
  }
  sub YATT::Lite::Core::Template::list_parts {
    (my Template $self, my $type) = @_;
    return @{$self->{partlist}} unless defined $type;
    grep { UNIVERSAL::isa($_, $type) } @{$self->{partlist}}
  }
  sub YATT::Lite::Core::Template::node_source {
    (my Template $tmpl, my $node) = @_;
    unless (ref $node eq 'ARRAY') {
      confess "Node is not an ARRAY";
    }
    $tmpl->source_region($node->[NODE_BEGIN], $node->[NODE_END]);
  }
  sub YATT::Lite::Core::Template::node_body_source {
    (my Template $tmpl, my $node) = @_;
    unless (ref $node eq 'ARRAY') {
      confess "Node is not an ARRAY";
    }
    $tmpl->source_region($node->[NODE_BODY_BEGIN], $node->[NODE_BODY_END]);
  }
  sub YATT::Lite::Core::Template::source_region {
    (my Template $tmpl, my ($begin, $end)) = @_;
    $tmpl->source_substr($begin, $end - $begin);
  }
  sub YATT::Lite::Core::Template::source_substr {
    (my Template $tmpl, my ($offset, $len)) = @_;
    unless (defined $len) {
      substr $tmpl->{cf_string}, $offset;
    } else {
      return undef if $len < 0;
      substr $tmpl->{cf_string}, $offset, $len;
    }
  }

  sub YATT::Lite::Core::Part::reorder_hash_params {
    (my Widget $widget, my ($params)) = @_;
    my @params;
    foreach my $name (map($_ ? @$_ : (), $widget->{arg_order})) {
      push @params, delete $params->{$name};
    }
    if (keys %$params) {
      die "Unknown args for $widget->{cf_name}: " . join(", ", keys %$params);
    }
    wantarray ? @params : \@params;
  }

  sub YATT::Lite::Core::Part::reorder_cgi_params {
    (my Widget $widget, my ($cgi, $list)) = @_;
    $list ||= [];
    foreach my $name ($cgi->param) {
      next unless $name =~ /^\w+$/;
      my $argdecl = $widget->{arg_dict}{$name}
	or die "Unknown args for widget '$widget->{cf_name}': $name";
      my @value = $cgi->param($name);
      $list->[$argdecl->argno] = $argdecl->type eq 'list'
	? \@value : $value[0];
    }
    @$list;
  }
}
#========================================
sub configure_rc_script {
  (my MY $vfs, my $script) = @_;
  my $pkg = $vfs->{root}->{cf_package}
    or die $vfs->error("package name is not specified for configure rc_script");
  # print STDERR "#### $pkg \n";
  # XXX: base は設定済みだったはずだけど...
  ckeval(qq{package $pkg; use strict; use YATT::Lite::Entities; $script});
}
#========================================

# Template alias さえ拡張すれば済むように。
# 逆に言うと、 vfs_file だけを定義して Template を定義しなかった場合, 継承が働かなくなった。
sub create_file {
  (my MY $vfs, my $spec) = splice @_, 0, 2;
  $vfs->Template->new(path => $spec, @_);
}

#========================================
{
  sub Parser {require YATT::Lite::LRXML; 'YATT::Lite::LRXML'}
  sub cgen_perl { 'YATT::Lite::CGen::Perl' }
  sub stat_mtime {
    my ($fn) = @_;
    -e $fn or return;
    (stat($fn))[9];
  }
  sub get_parser {
    my MY $self = shift;
    # $self->{parser} ||=
      $self->Parser->new
	(vfs => $self, $self->cf_delegate
	 (qw(namespace special_entities)
	  , [debug_parser => 'debug']
	  , [tmpl_encoding => 'encoding']
	 )
	 , $self->{cf_parse_while_loading} ? (all => 1) : ()
	 , @_);
  }
  sub ensure_parsed {
    (my MY $self, my Widget $widget) = @_;
    $self->get_parser->parse_body($widget->{cf_folder});
    # $self->get_parser->parse_widget($widget)
    @{$widget->{tree}};
  }
  sub render {
    my MY $self = shift;
    open my $fh, '>', \ (my $str = "") or die "Can't open capture buffer!: $!";
    $self->render_into($fh, @_);
    close $fh;
    $str;
  }
  sub render_into {
    (my MY $self, my ($fh, $name, @args)) = @_;
    my ($sub, $pkg) = $self->find_renderer($name);
    $sub->($pkg, $fh, @args);
  }

  # root から見える part (と、その template)を取り出す。
  sub get_part {
    (my MY $self, my $name, my %opts) = @_;
    my $ignore_error = delete $opts{ignore_error};
    my Template $tmpl;
    my Part $part;
    if (UNIVERSAL::isa($self->{root}, Template)) {
      $tmpl = $self->{root};
      $part = $self->find_part($name);
    } else {
      $tmpl = $self->find_file($name)
	or ($ignore_error and return)
	  or croak "No such template file: $name";
      $part = $tmpl->{Item}{''};
    }
    # XXX: それとも、 $part から $tmpl が引けるようにするか? weaken して...
    wantarray ? ($part, $tmpl) : $part;
  }

  # part を保持する template を取り出す。
  sub find_template_for_part {
    (my MY $self, my $name) = @_;
    if (UNIVERSAL::isa($self->{root}, Template)) {
      $self->{root};
    } else {
      $self->find_file($name)
    }
  }

  sub find_part_handler {
    (my MY $self, my $nameSpec, my %opts) = @_;
    my $ignore_error = delete $opts{ignore_error};
    my ($partName, $subPage, $action) = ref $nameSpec ? @$nameSpec : $nameSpec;
    $subPage //= '';

    my ($itemKey, $method) = do {
      if (defined $action) {
	("do_$action") x 2;
      } else {
	($subPage, "render_$subPage");
      }
    };

    my Template $tmpl = $self->find_template_for_part($partName)
      or ($ignore_error and return)
	or croak "No such template file: $partName";

    my Part $part = $tmpl->{Item}{$itemKey}
      or ($ignore_error and return)
	or croak "No such item in file $partName: $itemKey";

    my $pkg = $self->find_product(perl => $tmpl)
      or ($ignore_error and return)
	or croak "Can't compile template file: $partName";

    my $sub = $pkg->can($method)
      or ($ignore_error and return)
	or croak "Can't extract $method from file: $partName";

    ($part, $sub, $pkg);
  }

  sub find_renderer {
    my MY $self = shift;
    my ($part, $sub, $pkg) = $self->find_part_handler(@_)
      or return;
    wantarray ? ($sub, $pkg) : $sub;
  }

  # DirHandler INST 固有 CGEN_perl の生成
  sub get_cgen_class {
    (my MY $self, my $type) = @_;
    my $sub = $self->can("cgen_$type")
      || carp "Unknown product type: $type";
    $self->{cgen_class}{$type} ||= do {
      my $cg_base = $sub->();
      # XXX: ref($facade) が INST 固有に成ってなかったら？
      my $instpkg = ref($self->{cf_facade})."::CGEN_$type";
      ckeval(qq|package $instpkg; use base qw($cg_base)|);
      $instpkg;
    };
  }

  # XXX: Action only コンパイルは？
  sub find_product {
    (my MY $self, my $spec, my Template $tmpl, my %opts) = @_;
    my ($type, $kind) = ref $spec ? @$spec : $spec;
    # local $YATT = $self;
    unless ($tmpl->{product}{$type}) {
      my $cg_class = $self->get_cgen_class($type);
      my $cgen = $cg_class->new
	(vfs => $self
	 , $self->cf_delegate(qw(no_lineinfo check_lineno only_parse))
	 , parser => $self->get_parser
	 , sink => $opts{sink} || sub {
	   my ($info, @script) = @_;
	   print @script, "\n" if $self->{cf_debug_cgen};
	   ckeval(@script);
	 });
      # 二重生成防止のため、代入自体は ensure_generated の中で行う。
      $cgen->ensure_generated($spec => $tmpl);
    };
    $tmpl->{product}{$type};
  }
  sub YATT::Lite::Core::Template::after_create {
    (my Template $tmpl, my MY $self) = @_;
    # XXX: ここでは SUPER が使えない。
    $tmpl->YATT::Lite::VFS::File::after_create($self);
    ($tmpl->{cf_name}) = $tmpl->{cf_path} =~ m{(\w+)\.\w+$}
      or $self->error("Can't extract part name from '%s'", [$tmpl->{cf_path}])
	if not defined $tmpl->{cf_name} and defined $tmpl->{cf_path};
  }
  sub YATT::Lite::Core::Template::reset {
    (my Template $tmpl) = @_;
    $tmpl->YATT::Lite::VFS::File::reset;
    undef $tmpl->{product};
    undef $tmpl->{parse_ok};
    # delpkg($tmpl->{cf_package}); # No way to avoid redef error.
  }
  sub YATT::Lite::Core::Template::refresh {
    (my Template $tmpl, my MY $self) = @_;
    if ($tmpl->{cf_path}) {
      my $mtime = stat_mtime($tmpl->{cf_path});
      unless (defined $mtime) {
	return; # XXX: ファイルが消された
      } elsif (defined $tmpl->{cf_mtime} and $tmpl->{cf_mtime} >= $mtime) {
	return; # timestamp は、キャッシュと同じかむしろ古い
      }
      $tmpl->{cf_mtime} = $mtime;
      my $parser = $self->get_parser;
      # decl のみ parse.
      # XXX: $tmpl->{cf_package} の指すパッケージをこの段階で map {undef $_}
      # すべきではないか?
      $parser->load_file_into($tmpl, $tmpl->{cf_path});
    } elsif ($tmpl->{cf_string}) {
      my $parser = $self->get_parser;
      $parser->load_string_into($tmpl, $tmpl->{cf_string}
				, scheme => "data", path => $tmpl->{cf_name});
    } else {
      return;
    }
    $tmpl;
  }
  sub YATT::Lite::Core::Widget::fixup {
    (my Widget $widget, my Template $tmpl, my $parser) = @_;
    foreach my $argName (@{$widget->{arg_order}}) {
      $widget->{has_required_arg} = 1
	if $widget->{arg_dict}{$argName}->is_required;
    }
    $widget->{arg_dict}{body} ||= do {
      # lineno も入れるべきかも。 $widget->{cf_bodyln} あたり.
      my $var = $parser->mkvar_at(undef, code => 'body'
				  , scalar @{$widget->{arg_order} ||= []});
      push @{$widget->{arg_order}}, 'body';
      $var;
    };
  }
}

sub find_template_from_package {
  (my MY $self, my $pkg) = @_;
  $self->{pkg2folder}{$pkg};
}

# XXX: 廃止予定。YATT::Lite::Factory (isa NSBuilder dedicated to YATT::Lite)
# XXX: に取って代わられる, はず。
sub rootns_for {
  my $pack = shift;
  my $outerns = ref $_[0] || $_[0];
  build_entns(ROOT => $outerns, build_entns(EntNS => $outerns, $pack->EntNS));
}

use YATT::Lite::Breakpoint ();
YATT::Lite::Breakpoint::break_load_core();

1;
