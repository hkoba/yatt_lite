package YATT::Lite::WebMVC0::App; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use parent qw/YATT::Lite/;
use YATT::Lite::MFields qw/cf_session_opts
	      cf_header_charset
	      cf_is_gateway

	      Action
	    /;

use YATT::Lite::WebMVC0::Connection;
sub Connection () {'YATT::Lite::WebMVC0::Connection'}

use Carp;
use YATT::Lite::Util qw(cached_in ckeval
			dofile_in compile_file_in
		      );

# sub handle_ydo, _do, _psgi...

sub handle {
  my MY $self = shift;
  chdir($self->{cf_dir})
    or die "Can't chdir '$self->{cf_dir}': $!";
  local $SIG{__WARN__} = sub {
    die $self->make_error(2, {reason => $_[0]});
  };
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
# XXX: Should handle union mount!
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
	 $sub = compile_file_in($self->{cf_app_ns}, $path);
       }
       @{$item} = ($sub, $age);
     });
  return unless defined $item and $item->[0];
  wantarray ? @$item : $item->[0];
}

#========================================
sub error_handler {
  (my MY $self, my ($type, $err)) = @_;
  # どこに出力するか、って問題も有る。 $CON を rewind すべき？
  my $errcon = do {
    if (my $con = $self->CON) {
      $con->as_error;
    } else {
      # XXX: is_gateway が形骸化してる。
      $self->make_connection(\*STDOUT, is_gateway => $self->{cf_is_gateway});
    }
  };
  # error.ytmpl を探し、あれば呼び出す。
  my ($sub, $pkg) = $self->find_renderer($type => ignore_error => 1) or do {
    # print {*$errcon} $err, Carp::longmess(), "\n\n";
    # Dispatcher の show_error に任せる
    die $err;
  };
  $sub->($pkg, $errcon, $err);
  $errcon->commit; # XXX: これが無いと、 500 error, 有っても無限再帰。
  $self->DONE; # XXX: bailout と分けるべき
}

use YATT::Lite::Breakpoint;
YATT::Lite::Breakpoint::break_load_dirhandler();

1;
