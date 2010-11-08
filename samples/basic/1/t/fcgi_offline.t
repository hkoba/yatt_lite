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

my $CLASS = Test::FCGI::Auto->class
  or Test::FCGI::Auto->skip_all
  ('None of FCGI::Client and /usr/bin/cgi-fcgi is available');

unless (eval {require Test::Differences}) {
  $CLASS->skip_all('Test::Differences is not installed');
}

my $mech = $CLASS->new
  (map {
    (rootdir => $_
     , fcgiscript => "$_/cgi-bin/runyatt.fcgi")
  } File::Spec->rel2abs("$bindir/.."));

if (my $reason = $mech->check_skip_reason) {
  $mech->skip_all($reason);
}

sub MY () {__PACKAGE__}
use YATT::Lite::Breakpoint;
use YATT::Lite::XHFTest2;
use base qw(YATT::Lite::XHFTest2);
use YATT::Lite::Util qw(lexpand);

use 5.010;

my MY $tests = MY->load_tests([dir => "$bindir/.."
			       , libdir => untaint_any
			       (File::Spec->rel2abs($libdir))]
			      , @ARGV ? @ARGV : $bindir);
$tests->enter;

my @plan = $tests->test_plan;
# skip_all should be called before fork.
if (@plan and $plan[0] eq 'skip_all') {
  $mech->plan(@plan);
}

$mech->fork_server
  (sub {

     # test plan should be configured after fork.
     $mech->plan(@plan);

     $tests->mechanized($mech);

   });

sub base_url { shift; '/'; }

sub ntests_per_item {
  (my MY $tests, my Item $item) = @_;
  lexpand($item->{cf_HEADER})/2
    + (($item->{cf_BODY} || $item->{cf_ERROR}) ? 1 : 0);
}

sub mech_request {
  (my MY $tests, my $mech, my Item $item) = @_;
  my $method = $tests->item_method($item);
  my $url = $tests->item_url_file($item);
  $mech->request($method, $url, $item->{cf_PARAM});
}

#========================================
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
      my @opts = qw(-T);
      if (my $switch = $ENV{HARNESS_PERL_SWITCHES}) {
	push @opts, split " ", $switch;
      }
      exec $^X, @opts, $self->{cf_fcgiscript};
      die "Can't exec $self->{cf_fcgiscript}: $!";
    }
  }

  sub parse_result {
    my MY $self = shift;
    # print map {"#[[$_]]\n"} split /\n/, $result;
    $self->{res} = HTTP::Response->parse(shift);
  }

  sub content {
    my MY $self = shift;
    defined $self->{res} ? $self->{res}->content : undef;
  }


  use Carp;
  use YATT::Lite::Util qw(url_encode);
  sub encode_querystring {
    (my MY $self, my ($query, $sep)) = @_;
    if (not defined $query or not ref $query) {
      $query
    } elsif (ref $query eq 'HASH') {
      join($sep // ';'
	   , map {
	     $self->url_encode($_) . '='
	       . $self->url_encode($query->{$_})
	   } keys %$query);
    } else {
      croak "Not implemented type of PARAM!";
    }
  }

  #========================================
  package Test::FCGI::Auto; sub MY () {__PACKAGE__}
  use base qw(Test::FCGI);
  sub class {
    my $pack = shift;
    if (eval {require FCGI::Client}) {
      'Test::FCGI::Client';
    } elsif ($pack->which('cgi-fcgi')) {
      'Test::FCGI::via_cgi_fcgi';
    }
  }

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

  use YATT::Lite::Util qw(terse_dump);
  sub request {
    (my MY $self, my ($method, $path, $query)) = @_;
    require FCGI::Client;
    my $client = FCGI::Client::Connection->new
      (sock => $self->mkclientsock($self->{sockfile}));

    my $env = {REQUEST_METHOD    => uc($method)
	, REQUEST_URI     => $path
	, DOCUMENT_ROOT   => $self->{cf_rootdir}
	, PATH_TRANSLATED => "$self->{cf_rootdir}$path"};
    my @content;
    if (defined $query) {
      if ($env->{REQUEST_METHOD} eq 'GET') {
	$env->{QUERY_STRING} = $self->encode_querystring($query);
      } elsif ($env->{REQUEST_METHOD} eq 'POST') {
	$env->{CONTENT_TYPE} = 'application/x-www-form-urlencoded';
	my $enc = $self->encode_querystring($query);
	push @content, $enc;
	$env->{CONTENT_LENGTH} = length($enc);
      }
    }

    # print STDERR "# REQ: ", terse_dump($env, @content), "\n";

    ($self->{raw_result}, $self->{raw_error}) = $client->request
      ($env, @content);

    # print STDERR "# ANS: ", terse_dump($self->{raw_result}, $self->{raw_error}), "\n";

    unless (defined $self->{raw_result}) {
      $self->{res} = undef;
      return;
    }

    # Protocol 先頭行を保管する
    my $res = do {
      if ($self->{raw_result} =~ m{^HTTP/\d+\.\d+ \d+ }) {
	$self->{raw_result}
      } elsif ($self->{raw_result} =~ /^Status: (\d+ .*)/) {
	"HTTP/1.0 $1\x0d\x0a$self->{raw_result}"
      } else {
	"HTTP/1.0 200 Faked OK\x0d\x0a$self->{raw_result}"
      }
    };
    $self->parse_result($res);
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
    (my MY $self, my ($method, $path, $query)) = @_;
    # local $ENV{SERVER_SOFTWARE} = 'PERL_TEST_FCGI';
    local $ENV{GATEWAY_INTERFACE} = 'CGI/1.1';
    my $is_post = (local $ENV{REQUEST_METHOD} = uc($method)
		   =~ m{^(POST|PUT)$});
    local $ENV{REQUEST_URI} = $path;
    local $ENV{DOCUMENT_ROOT} = $self->{cf_rootdir};
    local $ENV{PATH_TRANSLATED} = "$self->{cf_rootdir}$path";
    local $ENV{QUERY_STRING} = $self->encode_querystring($query)
      unless $is_post;
    local $ENV{CONTENT_TYPE} = 'application/x-www-form-urlencoded'
      if $is_post;
    my $enc = $self->encode_querystring($query);
    local $ENV{CONTENT_LENGTH} = length $enc
      if $is_post;

    # XXX: open3
    my $kid = open2 my $read, my $write
      , $self->{wrapper}, qw(-bind -connect) => $self->{sockfile}
	or die "Can't invoke $self->{wrapper}: $!";
    if ($is_post) {
      print $write $enc;
    }
    close $write;

    #XXX: waitpid
    $self->parse_result(do {local $/; <$read>});
  }
}
