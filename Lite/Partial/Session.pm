package YATT::Lite::Partial::Session;
sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw/all/;

use YATT::Lite::Partial
  (requires => [qw/error
		   app_path_ensure_existing/]
   , fields => [qw/cf_session_driver
		   cf_session_config/]
  );

use YATT::Lite::Util qw/lexpand/;

#========================================

use YATT::Lite::WebMVC0::Connection;
sub Connection () {'YATT::Lite::WebMVC0::Connection'}
sub ConnProp () {Connection}

#========================================
# Session support, based on CGI::Session.

#
# This will be called back from $CON->get_session.
#
sub session_load {
  my MY $self = shift;
  my ConnProp $prop = (my $con = shift)->prop;
  my ($brand_new, @with_init) = @_;

  require CGI::Session;
  my $method = $brand_new ? 'new' : 'load';

  my ($type, %driver_opts) = $self->session_driver;

  my %opts = $self->{cf_session_config}
    ? lexpand($self->{cf_session_config})
      : $self->default_session_config;

  my $expire = delete($opts{expire}) // $self->default_session_expire;
  my $sid_key = $opts{name} ||= $self->default_session_sid_key;
  my ($sid) = map {defined $_ ? $_->value : ()} $con->cookies_in->{$sid_key};

  my $sess = CGI::Session->$method($type, $sid, \%driver_opts, \%opts);
  unless ($sess) {
    if ($brand_new) {
      $self->error("Session object is empty! mode: %s, sid: %s"
		   , $brand_new // '(none)', $sid // '(undef)');
      # return $prop->{session} = undef;
    } else {
      $sess = CGI::Session->new($type, undef, \%driver_opts, \%opts);
    }
  }

  $sess->expire($expire);

  if ($brand_new and $sess->is_new) {
    $con->set_cookie($sid_key, $sess->id, -path => $con->location);
  }

  foreach my $spec (@with_init) {
      if (ref $spec eq 'ARRAY') {
	my ($name, @value) = @$spec;
	$sess->param($name, @value > 1 ? \@value : $value[0]);
      } elsif (not ref $spec or ref $spec eq 'Regexp') {
	$spec = qr{^\Q$spec} unless ref $spec;
	foreach my $name ($con->param) {
	  next unless $name =~ $spec;
	  my (@value) = $con->param($name);
	  $sess->param($name, @value > 1 ? \@value : $value[0]);
	}
      } else {
	$self->error("Invalid session initializer: %s"
		     , terse_dump($spec));
      }
  }

  $prop->{session} = $sess;
}

sub session_driver {
  (my MY $self) = @_;
  $self->{cf_session_driver}
    ? lexpand($self->{cf_session_driver})
      : $self->default_session_driver;
}

sub session_delete {
  my MY $self = shift;
  my ConnProp $prop = (my $con = shift)->prop;
  if (my $sess = delete $prop->{session}) {
    $sess->delete;
    $sess->flush;
  }
  my $name = $self->{cf_session_config}{name} || $self->default_session_sid_key;
  my @rm = ($name, '', -expires => '-10y', -path => $con->location);
  $con->set_cookie(@rm);
}

sub session_flush {
  my MY $self = shift;
  my ConnProp $prop = (my $glob = shift)->prop;
  my $sess = $prop->{session}
    or return;
  return if $sess->errstr;
  $sess->flush;
  if (my $err = $sess->errstr) {
    local $prop->{session};
    $self->error("Can't flush session: %s", $err);
  }
}

sub configure_use_session {
  (my MY $self, my $value) = @_;
  if ($value) {
    $self->{cf_session_config}
      //= ref $value ? $value : [$self->default_session_config];
    $self->{cf_session_driver} //= [$self->default_session_driver];
  }
}

sub default_session_expire  { '1d' }
sub default_session_sid_key { 'SID' }
sub default_session_config  {}

sub default_session_driver  {
  (my MY $self) = @_;
  ("driver:file"
   , Directory => $self->app_path_ensure_existing('@var/tmp/sess')
  )
}


sub cmd_session_list {
  (my MY $self, my @param) = @_;
  print join("\t", qw(id created accessed), @param), "\n";
  require CGI::Session;
  my ($type, %driver_opts) = $self->session_driver;
  CGI::Session->find($type, sub {
    my ($sess) = @_;
    print join("\t", map {defined $_ ? $_ : "(undef)"}
	       $sess->id, $sess->ctime, $sess->atime
	       , map {$sess->param($_)} @param), "\n";
  }, \%driver_opts);
}

1;
