package YATT::Lite::PSGIEnv; sub Env () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);

my @PSGI_FIELDS;
BEGIN {
  @PSGI_FIELDS
    = qw(
	  HTTPS
	  GATEWAY_INTERFACE
	  REQUEST_METHOD
	  SCRIPT_NAME
	  SCRIPT_FILENAME
	  DOCUMENT_ROOT

	  PATH_INFO
	  PATH_TRANSLATED
	  REDIRECT_STATUS
	  REQUEST_URI
	  DOCUMENT_URI

	  QUERY_STRING
	  SERVER_NAME
	  SERVER_PORT
	  SERVER_PROTOCOL
	  HTTP_USER_AGENT
	  HTTP_REFERER
	  HTTP_COOKIE
	  HTTP_FORWARDED
	  HTTP_HOST
	  HTTP_PROXY_CONNECTION
	  HTTP_ACCEPT

	  psgi.version
	  psgi.url_scheme
	  psgi.input
	  psgi.errors
	  psgi.multithread
	  psgi.multiprocess
	  psgi.run_once
	  psgi.nonblocking
	  psgi.streaming
	  psgix.session
	  psgix.session.options
	  psgix.logger
       );
}

use fields @PSGI_FIELDS;

use YATT::Lite::Util qw(ckeval);

sub import {
  my ($myPack, @more_fields) = @_;

  my $callpack = caller;
  my $envname = $callpack . "::Env";
  my $sym = do {no strict 'refs'; \*{$envname}};


  my $script = sprintf(q|package %s; use base qw(%s);|
		       , $envname, __PACKAGE__);
  $script .= sprintf(q|use fields qw(%s);|, join " ", @more_fields)
    if @more_fields;

  ckeval($script);

  *$sym = sub () { $envname };
}

sub psgi_fields {
  wantarray ? @PSGI_FIELDS : {map {$_ => 1} @PSGI_FIELDS};
}

sub psgi_simple_env {
  my ($pack) = shift;
  my Env $given = {@_};
  my Env $env = {};
  $env->{'psgi.version'} = [1, 1];
  $env->{'psgi.url_scheme'} = 'http';
  $env->{'psgi.input'} = \*STDIN;
  $env->{'psgi.errors'} = \*STDERR;
  $env->{'psgi.multithread'} = 0;
  $env->{'psgi.multiprocess'} = 0;
  $env->{'psgi.run_once'} = 0;
  $env->{'psgi.nonblocking'} = 0;
  $env->{'psgi.streaming'} = 0;

  $env->{PATH_INFO} = $given->{PATH_INFO} || '/';

  $env;
}

1;
