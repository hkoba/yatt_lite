#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}
use base qw(File::Spec);
use File::Basename;

use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
my $libdir;
BEGIN {
  unless (grep {$_ eq 'YATT'} MY->splitdir($FindBin::Bin)) {
    die "Can't find YATT in runtime path: $FindBin::Bin\n";
  }
  $libdir = dirname(dirname(untaint_any($FindBin::Bin)));
}
use lib $libdir;
#----------------------------------------

use Test::More qw(no_plan);
use YATT::Lite::Util qw(appname rootname);
sub myapp {join _ => MyTest => appname($0), @_}

require_ok('YATT::Lite');
require_ok('YATT::Lite::Connection');

my $i = 1;
{
  my $yatt = new YATT::Lite(app_ns => myapp($i)
			    , vfs => [data => {foo => 'bar'}]
			    , die_in_error => 1
			    , debug_cgen => $ENV{DEBUG});

  {
    my $con = YATT::Lite::Connection->create;
    print {$con} "foo", "bar";
    print {$con} "baz";
    $con->flush;

    is $con->buffer, "foobarbaz", "Connection output";

    $con->set_header('Content-type', 'text/html');
    $con->set_header('X-Test', 'test');

    is_deeply {$con->list_header}
      , {'Content-type' => 'text/html', 'X-Test', 'test'}
	, "con->list_header";

    is $con->cget('encoding'), undef, "cget => undef";
    $con->configure(encoding => 'utf-8');
    is $con->cget('encoding'), 'utf-8', "cget => utf-8";

    eval {
      $con->error("Trivial error '%s'", 'MyError');
    };

    like $@, qr{^Trivial error 'MyError'}, '$con->error';

    eval {
      $con->raise(alert => "Trivial alert '%s'", 'MyAlert');
    };

    like $@, qr{^Trivial alert 'MyAlert'}, '$con->raise(alert)';
  }

  # ファイルに書けるか
  # header 周りの finalize はどうか。

  # もっと API を Plack::Request, Plack::Response に頼ったり、似せたりしてはどうか
  # もしくは Apache2::RequestRec に。
}

$i++;
{
  my $yatt = new YATT::Lite(app_ns => myapp($i)
			    , vfs => [data => {foo => 'bar'}]
			    , die_in_error => 1
			    , debug_cgen => $ENV{DEBUG});

  {
    package MyBackend1; sub MY () {__PACKAGE__}
    use base qw/YATT::Lite::Object/;
    use fields qw/cf_models cf_name/;
    sub model {
      (my MY $self, my $name) = @_;
      $self->{cf_models}{$name};
    }
  }
  my $backend = MyBackend1->new
    (name => 'Test', models => {foo => 'bar', bar => 3});;
  {
    my $con = YATT::Lite::Connection->create(undef, backend => $backend);
    is $con->backend(cget => 'name'), 'Test'
      , 'con->backend(method,@args)';
    is $con->model('foo'), 'bar'
      , 'con->model(foo)';
  }
}

# 次は YATT::Lite::WebMVC0 から make_connection して...

$i++;
require_ok('YATT::Lite::WebMVC0');
{

  my $mux = YATT::Lite::WebMVC0->new
    (doc_root => rootname($0) . ".d"
     , app_ns => myapp($i)
     , die_in_error => 1
     , debug_cgen => $ENV{DEBUG});

  {
    my $con = $mux->make_connection;
    print {$con} "foo", "bar";
    print {$con} "baz";
    $con->flush;

    is $con->buffer, "foobarbaz", "Connection output";

    is $con->request_path, "", "empty request path";
  }

  my $THEME;
  {
    $THEME = '/foo';
    my %env = qw(REQUEST_METHOD  GET
		 PATH_INFO       /foo
		 REQUEST_URI     /foo
		 HTTP_HOST       0.0.0.0:5000
		 SERVER_NAME     0
		 SERVER_PORT     5000
		 SERVER_PROTOCOL HTTP/1.1
		 HTTP_REFERER    http://example.com/
		 psgi.url_scheme http
	       );
    my $con = $mux->make_connection(undef, env => \%env);

    is $con->mkhost, '0.0.0.0:5000'
      , "[$THEME] mkhost()";
    is $con->mkurl, 'http://0.0.0.0:5000/foo'
      , "[$THEME] mkurl()";
    is $con->mkurl('bar'), 'http://0.0.0.0:5000/bar'
      , "[$THEME] mkurl(bar)";
    is $con->mkurl(undef, {bar => 'ba& z'})
      , 'http://0.0.0.0:5000/foo?bar=ba%26+z'
	, "[$THEME] mkurl(undef, {query})";
    is $con->mkurl(undef, undef, local => 1)
      , '/foo'
	, "[$THEME] mkurl(,,local => 1)";

    is $con->referer, 'http://example.com/', "[$THEME] referer";
  }

  {
    $THEME = '/';
    my %env = qw(REQUEST_METHOD  GET
		 PATH_INFO       /
		 REQUEST_URI     /
		 HTTP_HOST       0.0.0.0:5050
		 SERVER_NAME     0
		 SERVER_PORT     5000
		 SERVER_PROTOCOL HTTP/1.1
		 psgi.url_scheme http
	       );
    my $con = $mux->make_connection(undef, env => \%env);

    is $con->mkhost, '0.0.0.0:5050', "[$THEME] mkhost()";

    '/foo' =~ m{/(\w+)}; # Fill $1.
    is $con->mkurl, 'http://0.0.0.0:5050/', "[$THEME] mkurl()";

    is $con->mkurl('bar'), 'http://0.0.0.0:5050/bar'
      , "[$THEME] mkurl(bar)";
    is $con->mkurl(undef, {bar => 'ba& z'})
      , 'http://0.0.0.0:5050/?bar=ba%26+z', "[$THEME] mkurl(undef, {query})";
    is $con->mkurl(undef, undef, local => 1), '/'
      , "[$THEME] mkurl(,,local => 1)";
  }

}
