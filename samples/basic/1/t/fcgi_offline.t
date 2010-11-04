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

  use base qw(YATT::Lite::Object);
  use fields qw(res status ct content
		cf_rootdir cf_script
	      ); # base form

  package Test::FCGI::via_cgi_fcgi; sub MY () {__PACKAGE__}
  use base qw(Test::FCGI File::Spec);
  use fields qw(sockfile wrapper);

  use IO::Socket::UNIX;
  use Fcntl;
  use POSIX ":sys_wait_h";
  use Time::HiRes qw(usleep);

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

  sub check_skip_reason {
    my MY $self = shift;

    unless (eval {require FCGI and require CGI::Fast}) {
      return 'FCGI.pm is not installed';
    }

    $self->{wrapper} = MY->which('cgi-fcgi')
      or return 'cgi-fcgi is not installed';

    unless (-x $self->{cf_script}) {
      return 'fcgi script is not runnable';
    }

    return;
  }

  sub mkpipe {
    shift; new IO::Socket::UNIX(Local => shift, Listen => 5);
  }

  use File::Basename;
  use HTTP::Response;
  use IPC::Open2;
  sub request {
    (my MY $self, my ($method, $path, @query)) = @_;
    local $ENV{SERVER_SOFTWARE} = 'PERL_TEST_FCGI';
    local $ENV{GATEWAY_INTERFACE} = 'CGI/1.1';
    my $is_post = (local $ENV{REQUEST_METHOD} = uc($method)
		   =~ m{^(POST|PUT)$});
    local $ENV{REQUEST_URI} = $path;
    local $ENV{DOCUMENT_ROOT} = $self->{cf_rootdir};
    local $ENV{PATH_TRANSLATED} = "$self->{cf_rootdir}$path";
    local $ENV{QUERY_STRING} = @query ? join("&", @query) : undef;

    open2 my $read, my $write
      , $self->{wrapper}, qw(-bind -connect) => $self->{sockfile}
	or die "Can't invoke $self->{wrapper}: $!";
    if ($is_post) {
    }
    close $write;

    my $result = do {local $/; <$read>};
    # print map {"#[[$_]]\n"} split /\n/, $result;
    $self->{res} = HTTP::Response->parse($result);
  }

  sub fork_server {
    (my MY $self, my $sub) = @_;

    my $sessdir  = MY->tmpdir . "/fcgitest$$";
    unless (mkdir $sessdir, 0700) {
      die "Can't mkdir $sessdir: $!";
    }

    my $sock = $self->mkpipe($self->{sockfile} = "$sessdir/socket");

    unless (defined(my $kid = fork)) {
      die "Can't fork: $!";
    } elsif ($kid) {
      # parent
      $sub->($self);

      kill USR1 => $kid; # To shutdown FCGI script. TERM is ng.
      waitpid($kid, 0);

      unlink $self->{sockfile} if -e $self->{sockfile};
      rmdir $sessdir;

    } else {
      # child
      open STDIN, '<&', $sock or die "kid: Can't reopen STDIN: $!";
      close STDOUT;
      exec $self->{cf_script};
      die "Can't exec $self->{cf_script}: $!";
    }
  }

  sub which {
    my ($pack, $exe) = @_;
    foreach my $path ($pack->path) {
      if (-x (my $fn = $pack->join($path, $exe))) {
	return $fn;
      }
    }
  }
}



my $mech = Test::FCGI::via_cgi_fcgi->new
  (map {
    (rootdir => $_
     , script => "$_/cgi-bin/runyatt.fcgi")
  } File::Spec->rel2abs("$bindir/.."));

if (my $reason = $mech->check_skip_reason) {
  $mech->skip_all($reason);
}

$mech->fork_server
  (sub {
     $mech->plan('no_plan');
     Test::More::ok(my $res = $mech->request(GET => '/index.yatt')
		    , "res ok");
     print map {"#<<$_>>\n"} split /\n/, $res->content;
   });
