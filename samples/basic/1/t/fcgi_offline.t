#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);

sub untaint_any {$_[0] =~ m{(.*)} and $1}
use File::Basename;
use File::Spec;
my ($bindir, $libdir);
use lib untaint_any
  (File::Spec->rel2abs
   ($libdir = ($bindir = dirname(untaint_any($0)))
    . "/../../../../runyatt.lib"));

{
  package Test::FCGI; sub MY () {__PACKAGE__}
  use Test::Builder ();
  my $Test = Test::Builder->new;

  use base qw(YATT::Lite::Object File::Spec);
  use fields qw(res status ct content
		sockfile
		raw_result
		cf_rootdir cf_fcgiscript
	      ); # base form

  sub check_skip_reason {
    my MY $self = shift;

    unless (eval {require FCGI and require CGI::Fast}) {
      return 'FCGI.pm is not installed';
    }

    return;
  }

  sub plan {
    shift;
    require Test::More;
    Test::More::plan(@_);
  }

  sub skip_all {
    shift;
    require Test::More;
    Test::More::plan(skip_all => shift);
  }

  sub which {
    my ($pack, $exe) = @_;
    foreach my $path ($pack->path) {
      if (-x (my $fn = $pack->join($path, $exe))) {
	return $fn;
      }
    }
  }

  use IO::Socket::UNIX;
  use Fcntl;
  use POSIX ":sys_wait_h";
  use Time::HiRes qw(usleep);

  sub mkservsock {
    shift; new IO::Socket::UNIX(Local => shift, Listen => 5);
  }
  sub mkclientsock {
    shift; new IO::Socket::UNIX(Peer => shift);
  }

  sub fork_server {
    (my MY $self, my $sub) = @_;

    my $sessdir  = MY->tmpdir . "/fcgitest$$";
    unless (mkdir $sessdir, 0700) {
      die "Can't mkdir $sessdir: $!";
    }

    my $sock = $self->mkservsock($self->{sockfile} = "$sessdir/socket");

    unless (defined(my $kid = fork)) {
      die "Can't fork: $!";
    } elsif ($kid) {
      # parent
      $sub->($self);

      kill USR1 => $kid; # To shutdown FCGI fcgiscript. TERM is ng.
      waitpid($kid, 0);

      unlink $self->{sockfile} if -e $self->{sockfile};
      rmdir $sessdir;

    } else {
      # child
      open STDIN, '<&', $sock or die "kid: Can't reopen STDIN: $!";
      close STDOUT;
      # XXX: -MDevel::Cover=$ENV{HARNESS_PERL_SWITCHES}
      # XXX: Taint?
      exec $self->{cf_fcgiscript};
      die "Can't exec $self->{cf_fcgiscript}: $!";
    }
  }

  sub parse_result {
    my MY $self = shift;
    # print map {"#[[$_]]\n"} split /\n/, $result;
    $self->{res} = HTTP::Response->parse(shift);
  }

  #========================================
  package Test::FCGI::Client; sub MY () {__PACKAGE__}
  use base qw(Test::FCGI);
  use fields qw(connection raw_error);

  sub fork_server {
    my $self = shift;
    local $ENV{GATEWAY_INTERFACE} = 'CGI/1.1';
    $self->SUPER::fork_server(@_);
  }

  sub check_skip_reason {
    my MY $self = shift;

    my $reason = $self->SUPER::check_skip_reason;
    return $reason if $reason;

    unless (eval {require FCGI::Client}) {
      return 'FCGI::Client is not installed';
    }
    return
  }

  sub request {
    (my MY $self, my ($method, $path, @query)) = @_;
    require FCGI::Client;
    my $client = FCGI::Client::Connection->new
      (sock => $self->mkclientsock($self->{sockfile}));

    ($self->{raw_result}, $self->{raw_error}) = $client->request
      ({REQUEST_METHOD    => uc($method)
	, REQUEST_URI     => $path
	, DOCUMENT_ROOT   => $self->{cf_rootdir}
	, PATH_TRANSLATED => "$self->{cf_rootdir}$path"
	, (@query ? (QUERY_STRING => join("&", @query)) : ())});

    $self->parse_result($self->{raw_result});
  }

  #========================================
  package Test::FCGI::via_cgi_fcgi; sub MY () {__PACKAGE__}
  use base qw(Test::FCGI File::Spec);
  use fields qw(wrapper);

  sub check_skip_reason {
    my MY $self = shift;

    my $reason = $self->SUPER::check_skip_reason;
    return $reason if $reason;

    $self->{wrapper} = MY->which('cgi-fcgi')
      or return 'cgi-fcgi is not installed';

    unless (-x $self->{cf_fcgiscript}) {
      return 'fcgi fcgiscript is not runnable';
    }

    return;
  }

  use File::Basename;
  use HTTP::Response;
  use IPC::Open2;
  sub request {
    (my MY $self, my ($method, $path, @query)) = @_;
    # local $ENV{SERVER_SOFTWARE} = 'PERL_TEST_FCGI';
    local $ENV{GATEWAY_INTERFACE} = 'CGI/1.1';
    my $is_post = (local $ENV{REQUEST_METHOD} = uc($method)
		   =~ m{^(POST|PUT)$});
    local $ENV{REQUEST_URI} = $path;
    local $ENV{DOCUMENT_ROOT} = $self->{cf_rootdir};
    local $ENV{PATH_TRANSLATED} = "$self->{cf_rootdir}$path";
    local $ENV{QUERY_STRING} = @query ? join("&", @query) : undef;

    # XXX: open3
    my $kid = open2 my $read, my $write
      , $self->{wrapper}, qw(-bind -connect) => $self->{sockfile}
	or die "Can't invoke $self->{wrapper}: $!";
    if ($is_post) {
      # write....
    }
    close $write;

    #XXX: waitpid
    $self->parse_result(do {local $/; <$read>});
  }
}

# XXX: Automatic selection...
my $CLASS = 'Test::FCGI::Client';
# my $CLASS = 'Test::FCGI::via_cgi_fcgi';

my $mech = $CLASS->new
  (map {
    (rootdir => $_
     , fcgiscript => "$_/cgi-bin/runyatt.fcgi")
  } File::Spec->rel2abs("$bindir/.."));

if (my $reason = $mech->check_skip_reason) {
  $mech->skip_all($reason);
}

$mech->fork_server
  (sub {
     $mech->plan('no_plan');
     Test::More::ok(my $res = $mech->request(GET => '/index.yatt')
		    , "res ok");
     Test::More::like($res->content, qr{<title>Hello World!</title>}
		      , "title");
     Test::More::like($res->content, qr{<div id="body"[^>]*>\s*RUOK\?</div>}
		      , "div#body");
   });
