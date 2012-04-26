#!/usr/bin/perl -w
# -*- coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/lib");
use Test::More qw(no_plan);
use YATT::Lite::Util qw(appname rootname);
sub myapp {join _ => MyTest => appname($0), @_}

require_ok('YATT::Lite');

my $i = 1;
{
  my $yatt = new YATT::Lite(appns => myapp($i)
			    , vfs => [data => {foo => 'bar'}]
			    , die_in_error => 1
			    , debug_cgen => $ENV{DEBUG});

  {
    my $con = $yatt->make_connection;
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
  # header 周りの commit はどうか。

  # もっと API を Plack::Request, Plack::Response に頼ったり、似せたりしてはどうか
  # もしくは Apache2::RequestRec に。
}

# 次は YATT::Lite::WebMVC0::Toplevel から make_connection して...

$i++;
require_ok('YATT::Lite::WebMVC0::App');
{
  
  my $yatt = new YATT::Lite::WebMVC0::App
    (dir => rootname($0) . ".d"
     , appns => myapp($i)
     , die_in_error => 1
     , debug_cgen => $ENV{DEBUG});

  {
    my $con = $yatt->make_connection;
    print {$con} "foo", "bar";
    print {$con} "baz";
    $con->flush;

    is $con->buffer, "foobarbaz", "Connection output";

    is $con->request_path, "", "empty request path";
  }

  {
    my %env = qw(REQUEST_METHOD  GET
		 PATH_INFO       /foo
		 REQUEST_URI     /foo
		 HTTP_HOST       0.0.0.0:5000
		 SERVER_NAME     0
		 SERVER_PORT     5000
		 SERVER_PROTOCOL HTTP/1.1
		 psgi.url_scheme http
	       );
    my $con = $yatt->make_connection(undef, env => \%env);

    is $con->mkhost, '0.0.0.0:5000', "mkhost()";
    is $con->mkurl, 'http://0.0.0.0:5000/foo', "mkurl()";
    is $con->mkurl('bar'), 'http://0.0.0.0:5000/bar'
      , "mkurl(bar)";
    is $con->mkurl(undef, {bar => 'ba& z'})
      , 'http://0.0.0.0:5000/foo?bar=ba%26+z', "mkurl(undef, {query})";
    is $con->mkurl(undef, undef, local => 1), '/foo'
      , "mkurl(,,local => 1)";
  }

}
