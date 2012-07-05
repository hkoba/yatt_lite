package YATT::Lite::WebMVC0::App; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use YATT::Lite -as_base, qw/*SYS
			    Entity/;
use YATT::Lite::MFields qw/cf_header_charset
			   cf_dir_config

			   Action/;

use YATT::Lite::WebMVC0::Connection;
sub Connection () {'YATT::Lite::WebMVC0::Connection'}

use Carp;
use YATT::Lite::Util qw/cached_in ckeval
			dofile_in compile_file_in
			try_invoke
		      /;

# sub handle_ydo, _do, _psgi...

sub handle {
  (my MY $self, my ($type, $con, $file)) = @_;
  chdir($self->{cf_dir})
    or die "Can't chdir '$self->{cf_dir}': $!";
  local $SIG{__WARN__} = sub {
    die $self->make_error(2, {reason => $_[0]});
  };
#  local $SIG{__DIE__} = sub {
#    if (@_ == 1 and ref $_[0] eq 'ARRAY') {
#      die $_[0];
#    } else {
#      die $self->make_error(2, {reason => $_[0]});
#    }
#  };
  if (my $charset = $self->header_charset) {
    $con->set_charset($charset);
  }
  $self->SUPER::handle($type, $con, $file);
}

sub _handle_ydo {
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
# Response Header
#========================================

sub default_header_charset {''}
sub header_charset {
  (my MY $self) = @_;
  $self->{cf_header_charset} || $self->{cf_output_encoding}
    || $SYS->header_charset
      || $self->default_header_charset;
}

#========================================
sub error_handler {
  (my MY $self, my ($type, $err)) = @_;
  # どこに出力するか、って問題も有る。 $CON を rewind すべき？
  my $errcon = do {
    if (my $con = $self->CON) {
      $con->as_error;
    } elsif ($SYS) {
      $SYS->make_connection(\*STDOUT);
    } else {
      \*STDERR;
    }
  };
  # error.ytmpl を探し、あれば呼び出す。
  my ($sub, $pkg) = $self->find_renderer($type => ignore_error => 1) or do {
    # print {*$errcon} $err, Carp::longmess(), "\n\n";
    # Dispatcher の show_error に任せる
    die $err;
  };
  $sub->($pkg, $errcon, $err);
  try_invoke($errcon, 'flush_headers');
  $self->DONE; # XXX: bailout と分けるべき
}

Entity dir_config => sub {
  my ($this, $name) = @_;
  my MY $self = $this->YATT;
  return $self->{cf_dir_config} unless defined $name;
  $self->{cf_dir_config}{$name};
};

use YATT::Lite::Breakpoint;
YATT::Lite::Breakpoint::break_load_dirhandler();

1;
