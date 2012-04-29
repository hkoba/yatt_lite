package YATT::Lite; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use 5.010;
use Carp qw(carp croak confess longmess);
use version; our $VERSION = qv('v0.0.3_2');

#
# YATT 内部への Facade. YATT の初期化パラメータの保持者でもある。
#
use base qw(YATT::Lite::Object);
use fields qw(YATT
	      cf_dir
	      cf_vfs cf_base
	      cf_output_encoding
	      cf_tmpl_encoding
	      cf_app_ns entns
	      cf_debug_cgen cf_debug_parser cf_namespace cf_only_parse
	      cf_die_in_error cf_error_handler
	      cf_special_entities cf_no_lineinfo cf_check_lineno
	      cf_rc_script
	      cf_tmpl_cache
	      cf_at_done
	      cf_dont_map_args
	      cf_dont_debug_param
	      cf_info
	    );

# Entities を多重継承する理由は import も継承したいから。
# XXX: やっぱり、 YATT::Lite には固有の import を用意すべきではないか?
#   yatt_default や cgen_perl を定義するための。
use YATT::Lite::Entities -as_base, qw(*YATT);
use YATT::Lite::Util qw(globref lexpand extname ckrequire terse_dump escape
			set_inc
		      );

sub Facade () {__PACKAGE__}
sub default_trans {'YATT::Lite::Core'}

sub default_export {(shift->SUPER::default_export, qw(Entity *CON))}

our $CON;
sub symbol_CON { return *CON }
sub CON { return $CON }

#========================================
# Abstract connection
#========================================
require YATT::Lite::Connection;
sub Connection () {'YATT::Lite::Connection'}
sub make_connection {
  (my MY $self, my ($fh, @rest)) = @_;
  $self->Connection->create_for_yatt($self, $fh, @rest)
}

#========================================
# Output encoding
#========================================
sub fconfigure_encoding {
  my MY $self = shift;
  return unless $self->{cf_output_encoding};
  my $enc = "encoding($self->{cf_output_encoding})";
  require PerlIO;
  foreach my $fh (@_) {
    next if grep {$_ eq $enc} PerlIO::get_layers($fh);
    binmode($fh, ":$enc");
  }
  $self;
}

#========================================
# file extension based handler dispatching.
#========================================

# XXX: @rest の使い道、いまいち方針が固まらない。 Web層の事情と Core層の事情を分けるべきか?
sub handle {
  (my MY $self, my ($ext, $con, $file, @rest)) = @_;
  local ($YATT, $CON) = ($self, $con);
  unless (defined $file) {
    confess "\n\nFilename for DirHandler->handle() is undef!"
      ." in $self->{cf_app_ns}.\n";
  }

  my $sub = $self->find_handler($ext, $file);
  $sub->($self, $con, $file);

  $con;
}

sub render {
  my MY $self = shift;
  my $con = $self->make_connection;
  $self->render_into($con, @_);
  $con->commit;
  $con->buffer;

  # open my $fh, '>', \ (my $str = "") or die "Can't open capture buffer!: $!";
  # $self->render_into($fh, @_);
  # close $fh;
  # $str;
}

sub render_into {
  local ($YATT, $CON) = splice @_, 0, 2;
  $YATT->open_trans->render_into($CON, @_);
}

sub commit {
  local ($YATT, $CON) = @_;
  $CON->commit;
}

sub find_handler {
  (my MY $self, my ($ext, $file)) = @_;
  $ext //= $self->cut_ext($file) || 'yatt';
  # XXX: There should be optional hash based (extension => handler) mapping.
  # cf_ext_alias
  my $sub = $self->can("handle_$ext")
    or die "Unsupported file type: $ext";
  $sub;
}

sub map_request {
  (my MY $self, my ($con, $file)) = @_;
  my ($subpage, $action);
  # XXX: url_param
  foreach my $name (grep {defined} $con->param()) {
    my ($sigil, $word) = $name =~ /^([~!])(\1|\w*)$/
      or next;
    # If $name in ('~~', '!!'), use value.
    my $new = $word eq $sigil ? $con->param($name) : $word;
    # else use $word from ~$word.
    # Note: $word may eq ''. This is for render_/action_.
    given ($sigil) {
      when ('~') {
	if (defined $subpage) {
	  $self->error("Duplicate subpage request! %s vs %s"
		       , $subpage, $new);
	}
	$subpage = $new;
      }
      when ('!') {
	if (defined $action) {
	  $self->error("Duplicate action! %s vs %s"
		       , $action, $new);
	}
	$action = $new;
      }
      default {
	croak "Really?";
      }
    }
  }
  if (defined $subpage and defined $action) {
    # XXX: Reserved for future use.
    $self->error("Can't use subpage and action at one time: %s vs %s"
		 , $subpage, $action);
  } elsif (defined $subpage) {
    [$file, $subpage];
  } elsif (defined $action) {
    [$file, undef, $action];
  } else {
    $file;
  }
}

# 直接呼ぶことは禁止すべきではないか。∵ $YATT, $CON を設定するのは handle の役目だから。
sub handle_yatt {
  (my MY $self, my ($con, $file)) = @_;
  my $trans = $self->open_trans;

  my $mapped = $self->map_request($con, $file);
  if (not $self->{cf_dont_debug_param}
      and -e ".htdebug_param") {
    $self->dump($mapped, [map {[$_ => $con->param($_)]} $con->param]);
  }

  # XXX: public に限定するのはどこで？ ここで？それとも find_自体？
  my ($part, $sub, $pkg) = $trans->find_part_handler($mapped);
  unless ($part->public) {
    # XXX: refresh する手もあるだろう。
    croak $self->error(q|Forbidden request %s|, terse_dump($mapped));
  }
  # XXX: 未知引数エラーがあったら？
  $sub->($pkg, $con, $self->{cf_dont_map_args} || $part->isa($trans->Action)
	 ? ()
	 : $part->reorder_cgi_params($con));
  $con;
}

sub handle_ytmpl {
  (my MY $self, my ($con, $file)) = @_;
  # XXX: http result code:
  print $con "Forbidden filetype: $file";
}

sub cut_ext {
  my ($self, $fn) = @_;
  croak "Undefined filename!" unless defined $fn;
  return undef unless $fn =~ s/\.(\w+$)//;
  $1;
}

#========================================
# Delayed loading of YATT::Lite::Core
#========================================

sub open_trans {
  (my MY $self) = @_;
  my $trans = $self->get_trans;
  $trans->reset_refresh_mark;
  $trans;
}

sub get_trans {
  (my MY $self) = @_;
  $self->{YATT} || $self->build_trans($self->{cf_tmpl_cache});
}

sub build_trans {
  (my MY $self, my ($vfscache, $vfsspec, @rest)) = @_;
  my $class = $self->default_trans;
  ckrequire($class);

  my @vfsspec = @{$vfsspec || $self->{cf_vfs}};
  push @vfsspec, base => $self->{cf_base} if $self->{cf_base};

  $self->{YATT} = $class->new
    (\@vfsspec
     , facade => $self
     , cache => $vfscache
     , entns => $self->{entns}
     , @rest
     # XXX: Should be more extensible.
     , $self->cf_delegate_defined(qw(namespace base
				     die_in_error tmpl_encoding
				     debug_cgen debug_parser
				     special_entities no_lineinfo check_lineno
				     rc_script
				     only_parse)));
}

sub _after_after_new {
  (my MY $self) = @_;
  $self->{entns} = $self->ensure_entns($self->{cf_app_ns});
}

sub root_EntNS { 'YATT::Lite::Entities' }

# ${app_ns}::EntNS を作り、(YATT::Lite::Entities へ至る)継承関係を設定する。
# $app_ns に EntNS constant を追加する。
# XXX: 複数回呼んでも大丈夫か?
sub ensure_entns {
  my ($mypack, $app_ns) = @_;
  my $entns = "${app_ns}::EntNS";
  my $sym = do {no strict 'refs'; \*{$entns}};
  unless (UNIVERSAL::isa($app_ns, MY)) {
    add_base_to($app_ns, MY);
  }
  my $baseclass = do {
    if (my $sub = $app_ns->can("EntNS")) {
      $sub->();
    } else {
      $mypack->root_EntNS;
    }
  };
  unless (UNIVERSAL::isa($entns, $baseclass)) {
    add_base_to($entns, $baseclass);
  }
  set_inc($entns, 1);

  # EntNS を足すのは最後にしないと、再帰継承に陥る
  unless (my $code = *{$sym}{CODE}) {
    *$sym = sub () { $entns };
  } elsif ((my $old = $code->()) ne $entns) {
    croak "Can't add EntNS() to '$app_ns'. Already has EntNS as $old!";
  } else {
    # ok.
  }
  $entns
}

# use YATT::Lite qw(Entity); で呼ばれ、
# $callpack に Entity 登録関数を加える.
sub define_Entity {
  my ($myPack, $opts, $callpack, @base) = @_;

  # Entity を追加する先は、 $callpack が Object 系か、 memberless Pkg 系かによる
  # Object 系の場合は、 ::EntNS を作ってそちらに加える。
  # XXX: この判断ロジック自体を public API にするべきではないか？
  my $is_objclass = UNIVERSAL::isa($callpack, 'YATT::Lite::Object');
  my $destns = $is_objclass ? $myPack->ensure_entns($callpack, @base) : $callpack;

  # 既にあるなら何もしない。... バグの温床にならないことを祈る。
  my $ent = globref($callpack, 'Entity');
  unless (*{$ent}{CODE}) {
    *$ent = sub {
      my ($name, $sub) = @_;
      *{globref($destns, "entity_$name")} = $sub;
    };
  }

  if ($is_objclass) {
    *{globref($destns, 'YATT')} = *YATT;
  }
}

sub add_base_to {
  my ($pkg, $base) = @_;
  my $isa = globref($pkg, 'ISA');
  if (*{$isa}{ARRAY} and @{*{$isa}{ARRAY}}
      and ${*{$isa}{ARRAY}}[0] ne $base) {
    die "Inheritance confliction on $pkg: old=${*{$isa}{ARRAY}}[0] new=$base";
  }
  *$isa = [] unless *{$isa}{ARRAY};
  @{*{$isa}{ARRAY}} = $base;
  $pkg;
}

BEGIN {
  MY->define_Entity(undef, MY);
}

# YATT public? API, visible via Facade:
foreach
  (qw(find_part
      find_file
      find_product
      find_renderer
      find_part_handler
      ensure_parsed

      add_to
    )) {
  my $meth = $_;
  *{globref(MY, $meth)} = sub { shift->get_trans->$meth(@_) };
}

#========================================
# error reporting.
#========================================
# XXX: MY->error は, 結局使わないのでは?

sub error {
  (my MY $self) = map {ref $_ ? $_ : MY} shift;
  $self->raise(error => @_);
}

sub make_error {
  my ($self, $depth, $opts) = splice @_, 0, 3;
  my $fmt = $_[0];
  my ($pkg, $file, $line) = caller($depth);
  require YATT::Lite::Error;
  new YATT::Lite::Error
    (file => $opts->{file} // $file, line => $opts->{line} // $line
     , format => $fmt, args => [@_[1..$#_]]
     , backtrace => longmess()
     , $opts ? %$opts : ());
}

# $yatt->raise($errType => ?{opts}?, $errFmt, @fmtArgs)

sub raise {
  (my MY $self, my $type) = splice @_, 0, 2;
  my $opts = shift if @_ and ref $_[0] eq 'HASH';
  # shift/splice しないのは、引数を stack trace に残したいから
  my $err = $self->make_error(1 + (delete($opts->{depth}) // 1), $opts, @_);

  if (ref $self and my $sub = $self->{cf_error_handler}) {
    # $con を引数で引きずり回すのは大変なので、むしろ外から closure を渡そう、と。
    # $SIG{__DIE__} を使わないのはなぜかって? それはユーザに開放しておきたいのよん。
    $sub->($type, $err);
  } elsif ($sub = $self->can('error_handler')) {
    $sub->($self, $type, $err);
  } elsif (not ref $self or $self->{cf_die_in_error}) {
    die $err->message;
  } else {
    # 即座に die しないモードは、デバッガから error 呼び出し箇所に step して戻れるようにするため。
    # ... でも、受け側を do {my $err = $con->error; die $err} にでもしなきゃダメかも?
    return $err;
  }
}

# XXX: 将来、拡張されるかも。
sub DONE {
  my MY $self = shift;
  if (my $sub = $self->{cf_at_done}) {
    $sub->(@_);
  } else {
    die \ 'DONE';
  }
}

sub dump {
  my MY $self = shift;
  # XXX: charset...
  die [200, ["Content-type", "text/plain; charset=utf-8"]
       , [map {terse_dump($_)."\n"} @_]];
}

#========================================
# Builtin Entities.
#========================================

sub YATT::Lite::EntNS::entity_template {
  my ($this, $pkg) = @_;
  $YATT->get_trans->find_template_from_package($pkg // $this);
};

sub YATT::Lite::EntNS::entity_stash {
  my $this = shift;
  my $prop = $CON->prop;
  my $stash = $prop->{stash} //= {};
  unless (@_) {
    $stash
  } elsif (@_ > 1) {
    %$stash = @_;
  } elsif (not defined $_[0]) {
    carp "Undefined argument for :stash()";
  } elsif (ref $_[0]) {
    $prop->{stash} = $_[0]
  } else {
    $stash->{$_[0]};
  }
};

sub YATT::Lite::EntNS::entity_mkhidden {
  my ($this) = shift;
  \ join "\n", map {
    my $name = $_;
    my $esc = escape($name);
    map {
      sprintf(qq|<input type="hidden" name="%s" value="%s"/>|
	      , $esc, escape($_));
    } $CON->param($name);
  } @_;
};

#----------------------------------------
use YATT::Lite::Breakpoint ();
YATT::Lite::Breakpoint::break_load_facade();

1;