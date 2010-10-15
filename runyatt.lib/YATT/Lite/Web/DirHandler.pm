package YATT::Lite::Web::DirHandler; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Lite);
use fields qw(cf_dir
	      cf_session_opts
	      cf_output_encoding
	      cf_is_gateway

	      Action
	    );

use Carp;
use YATT::Lite::Util qw(cached_in ckeval);
use YATT::Lite::XHF;

sub new {
  my $pack = shift;
  # XXX: .htyattrc.pl �ϡ�
  unless (defined $_[0]) {
    confess "dir is undef!";
  }
  unless (-d $_[0]) {
    confess "No such directory '$_[0]'";
  }
  if (-e (my $rc = "$_[0]/.htyattrc.pl")) {
    dofile_in($pack, $rc);
  }
  my @opts = do {
    if (-e (my $cf = "$_[0]/.htyattconfig.xhf")) {
      load_xhf($cf);
    } else { () }
  };
  $pack->SUPER::new(dir => @_, @opts);
  # XXX: refresh �ϡ� <= �����Ǥ� DirHandler ¦�Τ��ƤФ�롣
}

# sub handle_ydo, _do, _psgi...

sub handle {
  my MY $self = shift;
  chdir($self->{cf_dir}) or die "Can't chdir '$self->{cf_dir}': $!";
  $self->SUPER::handle(@_);
}

sub handle_ydo {
  (my MY $self, my ($con, $file, @rest)) = @_;
  my $action = $self->get_action_handler($file)
    or die "Can't find action handler for file '$file'\n";

  # XXX: this �� EntNS pkg �� $YATT ��...
  $action->($self->EntNS, $con);
}

sub dofile_in {
  my ($pkg, $file) = @_;
  ckeval("package $pkg; do '$file' or die \$\@");
}

sub compile_file_in {
  my ($pkg, $file) = @_;
  my $sub = dofile_in($pkg, $file);
  unless (defined $sub and ref $sub eq 'CODE') {
    die "file '$file' should return CODE (but not)!\n";
  }
  $sub;
}

# XXX: cached_in ��������ݲ᤮�롣
# XXX: package per dir �ǡ��������ɤ��Τ�?
sub get_action_handler {
  (my MY $self, my $path) = @_;
  my $item = $self->cached_in
    ($self->{Action} //= {}, $path, $self, undef, sub {
       # first time.
       my ($self, $sys, $path) = @_;
       my $age = -M $path;
       my $sub = compile_file_in(ref $self, $path);
       [$sub, $age];
     }, sub {
       # second time
       my ($item, $sys, $path) = @_;
       my ($sub, $age);
       unless (defined ($age = -M $path)) {
	 # item is removed from filesystem, so undef $sub.
       } elsif ($$item[-1] == $age) {
	 return;
       } else {
	 $sub = compile_file_in($self->{cf_package}, $path);
       }
       @{$item} = ($sub, $age);
     });
  return unless defined $item and $item->[0];
  wantarray ? @$item : $item->[0];
}

#========================================
sub error_handler {
  (my MY $self, my $err) = @_;
  # �ɤ��˽��Ϥ��뤫���ä������ͭ�롣 $CON �� rewind ���٤���
  my $errcon = do {
    if (my $con = $self->CON) {
      $con->configure(is_error => 1); # �Ȥä�̵�����ɡ�
      # XXX: rewind ���������ɤ��ΤǤ�?
      $con;
    } else {
      \*STDOUT;
    }
  };
  # error.ytmpl ��õ��������иƤӽФ���
  if (my ($sub, $pkg) = $self->find_renderer(error => ignore_error => 1)) {
    $sub->($pkg, $errcon, $err);
    $errcon->commit; # ���줬̵���ȡ� 500 error.
    $self->DONE(1);
  } else {
    die $err;
  }
}

use YATT::Lite::Breakpoint;
YATT::Lite::Breakpoint::break_load_dirhandler();

1;
