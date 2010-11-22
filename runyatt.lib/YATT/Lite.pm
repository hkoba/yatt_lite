package YATT::Lite; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use 5.010;
use Carp;
use version; our $VERSION = qv('v0.0.2_3');

#
# YATT 内部への Facade. YATT の初期化パラメータの保持者でもある。
#
use base qw(YATT::Lite::Object);
use fields qw(YATT
	      cf_vfs cf_base
	      cf_output_encoding
	      cf_tmpl_encoding cf_package cf_nsbuilder
	      cf_debug_cgen cf_debug_parser cf_namespace cf_only_parse
	      cf_die_in_error cf_error_handler
	      cf_special_entities cf_no_lineinfo cf_check_lineno
	      cf_rc_script
	      cf_tmpl_cache
	      cf_at_done
	      cf_dont_map_args
	    );

# Entities を多重継承する理由は import も継承したいから。
# XXX: やっぱり、 YATT::Lite には固有の import を用意すべきではないか?
#   yatt_default や cgen_perl を定義するための。
use YATT::Lite::Entities -as_base, qw(Entity *YATT);
use YATT::Lite::Util qw(globref lexpand extname ckrequire terse_dump);

sub Facade () {__PACKAGE__}
sub default_trans {'YATT::Lite::Core'}

sub default_export {(shift->SUPER::default_export, qw(*CON))}

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
  $self->Connection->new($fh, @rest)
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
      ." in $self->{cf_package}.\n";
  }

  my $sub = $self->find_handler($ext, $file);
  $sub->($self, $con, $file);

  $con;
}

sub find_handler {
  (my MY $self, my ($ext, $file)) = @_;
  $ext //= $self->trim_ext($file) || 'yatt';
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
    my $new = $word eq $sigil ? $con->param($sigil) : $word;
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
  # $self->dump(@mapped, [$con->param]);

  # XXX: public に限定するのはどこで？ ここで？それとも find_自体？
  my ($part, $sub, $pkg) = $trans->find_part_handler($mapped);
  unless ($part->public) {
    # XXX: refresh する手もあるだろう。
    croak $self->error(q|Forbidden request '%s'|, terse_dump($mapped));
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
  print $con "Not Allowed: $file\n";
}

sub trim_ext {
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
     , @rest
     # XXX: Should be more extensible.
     , $self->cf_delegate_defined(qw(namespace package base nsbuilder
				     die_in_error tmpl_encoding
				     debug_cgen debug_parser
				     special_entities no_lineinfo check_lineno
				     rc_script
				     only_parse)));
}

# YATT public? API, visible via Facade:
foreach
  (qw(render
      render_into

      find_part
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

foreach
  (qw(rootns_for)) {
  my $meth = $_;
  *{globref(MY, $meth)} = sub {
    my $pack = shift;
    my $trans = $pack->default_trans;
    ckrequire($trans);
    my $sub = $trans->can($meth);
    $sub->($pack, @_);
  };
}

#========================================
# error reporting.
#========================================
# XXX: MY->error は, 結局使わないのでは?

sub error {
  (my MY $self) = map {ref $_ ? $_ : MY} shift;
  my $opts = shift if @_ and ref $_[0] eq 'HASH';
  # shift/splice しないのは、引数を stack trace に残したいから
  my $err = $self->make_error(1 + (delete($opts->{depth}) // 1), $opts, @_);
  $self->raise_error($err);
}

sub make_error {
  my ($self, $depth, $opts) = splice @_, 0, 3;
  my $fmt = $_[0];
  my ($pkg, $file, $line) = caller($depth);
  require YATT::Lite::Error;
  new YATT::Lite::Error
    (file => $opts->{file} // $file, line => $opts->{line} // $line
     , format => $fmt, args => [@_[1..$#_]]
     , $opts ? %$opts : ());
}

sub raise_error {
  (my MY $self, my $err) = @_;
  if (ref $self and my $sub = $self->{cf_error_handler}) {
    # $con を引数で引きずり回すのは大変なので、むしろ外から closure を渡そう、と。
    # $SIG{__DIE__} を使わないのはなぜかって? それはユーザに開放しておきたいのよん。
    $sub->($err);
  } elsif ($sub = $self->can('error_handler')) {
    $sub->($self, $err);
  } elsif (not ref $self or $self->{cf_die_in_error}) {
    die $err->message;
  } else {
    # 即座に die しないモードは、デバッガから error 呼び出し箇所に step して戻れるようにするため。
    # ... でも、受け側を mydie にでもしなきゃダメかも?
    return $err;
  }
}

# XXX: 将来、拡張されるかも。
sub DONE {
  my MY $self = shift;
  if (my $sub = $self->{cf_at_done}) {
    $sub->(@_);
  } else {
    exit @_;
  }
}

sub dump {
  my MY $self = shift;
  die terse_dump(@_);
}

#========================================
# Builtin Entities.
#========================================

Entity template => sub {
  my ($this, $pkg) = @_;
  $YATT->get_trans->find_template_from_package($pkg // $this);
};

#----------------------------------------
use YATT::Lite::Breakpoint ();
YATT::Lite::Breakpoint::break_load_facade();

1;

__END__

=head1 NAME

YATT::Lite - Yet Another Template Toolkit, Lightweight rewrite.

=head1 SYNOPSIS

  # Minimum case:
  use YATT::Lite;
  my $tmpl = q{
    <!yatt:args title who="?World">
    <h2>&yatt:title;</h2>
    Hello &yatt:who;!
  
    <!yatt:widget alter title who="?Space">
    <div class="title">&yatt:title;</div>
    <div class="body">
    Hello &yatt:who;!
    </div>
  };
  my $yatt = new YATT::Lite(vfs => [data => $tmpl], package => "MyApp");

  print $yatt->render("", "My First YATT"), "\n";
  # or
  $yatt->render_into(\*STDOUT, alter => "My Second YATT");

  # Multiple template.
  my $yatt2 = new YATT::Lite(vfs => [data => {foo => "..", bar => ".."}]
                             , package => "MyApp2");
  print $yatt2->render(foo => 1,2);
  print $yatt2->render(bar => 3,4);

  # And filesystem based templating.
  my $yatt3 = new YATT::Lite(vfs => [file => "my.yatt"], package => "MyApp3");
  my $yatt4 = new YATT::Lite(vfs => [dir  => "my.ytmpl"], package => "MyApp4");

=head1 DESCRIPTION

YATT is Yet Another Template Toolkit, aimed at Web Designers, rather
than well-trained programmers. To achieve this goal, YATT provides
more readable syntax for HTML/XML savvy designers, ``lint'' for static
syntax checking and many safer default behaviors, ie. automatic output
escaping based on argument type declaration and file extension based
visibility handling of template.

YATT::Lite is template-syntax-compatible, lightweight, full rewrite of
YATT with superior functionalities.

In YATT, basic building block is called ``widget''. Template text is
treated as a sequence of ``widget definition'', each of which is
leaded by ``widget declaration: <!yatt:widget>'', like multipart
email.

A widget is translated into a perl subroutine (on memory, currently).
A template text is translated into a perl package (class). The
translation is per-template basis and occurs on demand of
widget. Template can be given to YATT::Lite as a data(string/hash),
filename or directory name.

Package name of template is automatically generated with respect to
option and filepath. If template is loaded from filesystem, it is
cached and reloaded if modified.

Although widget is basically 'named', head of each template text can
be a ``unnamed (default) widget'', so that designers can treat a
template file itself as a widget. This means plain HTML files *just
works* as template set.

In future, mainline YATT will incorporate YATT::Lite interface. It
means, today, if you want to adapt next generation YATT before its
release, write your script using YATT::Lite.

This is (still) alpha release. Although template syntax and
facade(YATT::Lite) API became stable (I want), internal modules are
*open* for discussion.


=head1 INSTALLATION

It's all pure Perl, so it's ok to put the .pm files (or YATT directory tree)
in their appropriate local Perl subdirectories.
(But see NON-STANDARD DIRECTORY STRUCTURE)

The easiest way to install this distribution is:

    ./runyatt.lib/YATT/scripts/setup.zsh $TARGET_DIR

This will copy runyatt.cgi, mkdir runyatt.lib, symlink YATT in it and
create .htaccess for extension mapping. (Note: sorry, it needs Zsh)

Alternative, by-hand way is like:

    cd $TARGET_DIR
    ln -vnsf $DIST_DIR/runyatt.lib .
    install -m 755 $DIST_DIR/runyatt.cgi .

    # Then, map *.yatt to runyatt.cgi, like this:
    echo AddHandler x-yatt-handler .yatt .ydo > .htaccess
    echo Action x-yatt-handler $URL/runyatt.cgi >> .htaccess

=head1 NON-STANDARD DIRECTORY STRUCTURE

Unfortunately, YATT::Lite distribution doesn't conform
CPAN style standard directory structure. This is experimental,
but intentional. Because:

=over 4

=item 1 Engine(modules) and support scripts should be directory
bundled together.

To achieve this, scripts/* and elisp/* is placed in YATT/.

=item 2 Since YATT::Lite is still evolving, single (system-wide) installation
may not fit for multi-service site.

To isolate instability risk, individual service should have its own
installation of engine.  To achieve this, runyatt.cgi uses
runyatt.lib first.

=back

=head1 SUPPORT AND DOCUMENTATION

  You can also look for Source Code Repository at:

        http://github.com/hkoba/yatt_lite
        git://github.com/hkoba/yatt_lite.git


=head1 AUTHOR

"KOBAYASI, Hiroaki" <hkoba@cpan.org>

=head1 COPYRIGHT AND LICENCE

Copyright (C) 2007..2010 "KOBAYASI, Hiroaki"

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
