package YATT::Lite; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use Carp;
use version; our $VERSION = qv('0.0.1');

#
# YATT 内部への Facade. YATT の初期化パラメータの保持者でもある。
#
use base qw(YATT::Lite::Object);
use fields qw(YATT
	      cf_vfs cf_base
	      cf_tmpl_encoding cf_package cf_nsbuilder
	      cf_debug_cgen cf_debug_parser cf_namespace cf_only_parse
	      cf_die_in_error cf_error_handler
	      cf_special_entities cf_no_lineinfo cf_check_lineno
	      cf_rc_script
	      cf_tmpl_cache
	      cf_at_done
	    );

# Entities を多重継承する理由は import も継承したいから。
# XXX: やっぱり、 YATT::Lite には固有の import を用意すべきではないか?
#   yatt_default や cgen_perl を定義するための。
use YATT::Lite::Entities -as_base, qw(Entity *YATT);
use YATT::Lite::Util qw(globref lexpand extname);

sub Facade () {__PACKAGE__}
sub default_trans {require YATT::Lite::Core; 'YATT::Lite::Core'}

sub default_export {(shift->SUPER::default_export, qw(*CON))}

our $CON;
sub symbol_CON { return *CON }
sub CON { return $CON }

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

# 直接呼ぶことは禁止すべきではないか。∵ $YATT, $CON を設定するのは handle の役目だから。
sub handle_yatt {
  (my MY $self, my ($con, $file)) = @_;
  my $trans = $self->open_trans;

  # XXX: public に限定するのはどこで？ ここで？それとも find_自体？
  my ($part, $sub, $pkg) = $trans->find_part_handler($file);
  # XXX: 未知引数エラーがあったら？
  $sub->($pkg, $con, $part->reorder_cgi_params($con));
  $con;
}

sub handle_ytmpl {
  (my MY $self, my ($con, $file)) = @_;
  # XXX: http result code:
  print $con "Not Allowed: $file\n";
}

sub trim_ext {
  my ($self, $fn) = @_;
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
    my $sub = $pack->default_trans->can($meth);
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
