package YATT::Lite::Web::DirHandler; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Lite);
use fields qw(cf_dir
	      cf_session_opts
	      cf_output_encoding
	      cf_header_charset
	      cf_is_gateway

	      Action
	    );

use Carp;
use YATT::Lite::Util qw(cached_in ckeval
			dofile_in compile_file_in
		      );
use YATT::Lite::XHF;

sub new {
  my $pack = shift;
  # XXX: .htyattrc.pl は？
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
      # XXX: encoding?
      load_xhf($cf);
    } else { () }
  };
  $pack->SUPER::new(dir => @_, @opts);
  # XXX: refresh は？ <= 現状では DirHandler 側のが呼ばれる。
}

# sub handle_ydo, _do, _psgi...

sub handle {
  my MY $self = shift;
  chdir($self->{cf_dir})
    or die "Can't chdir '$self->{cf_dir}': $!";
  $self->SUPER::handle(@_);
}

sub handle_ydo {
  (my MY $self, my ($con, $file, @rest)) = @_;
  my $action = $self->get_action_handler($file)
    or die "Can't find action handler for file '$file'\n";

  # XXX: this は EntNS pkg か $YATT か...
  $action->($self->EntNS, $con);
}

# XXX: cached_in 周りは面倒過ぎる。
# XXX: package per dir で、本当に良いのか?
sub get_action_handler {
  (my MY $self, my $filename) = @_;
  my $path = "$self->{cf_dir}/$filename";
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
use YATT::Lite::Web::Connection;
sub Connection () {'YATT::Lite::Web::Connection'}
sub ConnProp () {Connection}

sub make_connection {
  (my MY $self, my ($fh, %opts)) = @_;
  $self->SUPER::make_connection(do {
    if ($opts{is_gateway}) {
      # buffered mode.
      (undef, parent_fh => $fh, header => sub {
	 my ($con) = shift;
	 $con->mkheader(-charset =>
			$$self{cf_header_charset} || $$self{cf_output_encoding}
			, $con->list_baked_cookie
		       );
       });
    } else {
      # direct mode.
      $fh
    }
  }, %opts);
}

#========================================
sub error_handler {
  (my MY $self, my $err) = @_;
  # どこに出力するか、って問題も有る。 $CON を rewind すべき？
  my $errcon = do {
    if (my $con = $self->CON) {
      $con->configure(is_error => 1); # 使って無いけど。
      # XXX: rewind した方が良いのでは?
      $con;
    } else {
      \*STDOUT;
    }
  };
  # error.ytmpl を探し、あれば呼び出す。
  if (my ($sub, $pkg) = $self->find_renderer(error => ignore_error => 1)) {
    $sub->($pkg, $errcon, $err);
    $errcon->commit; # これが無いと、 500 error.
    $self->DONE(1);
  } else {
    die $err;
  }
}

use YATT::Lite::Breakpoint;
YATT::Lite::Breakpoint::break_load_dirhandler();

1;
