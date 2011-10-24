#!/usr/bin/perl -w
# -*- coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/..");
use Test::More qw(no_plan);
use YATT::Lite::Util qw(appname rootname);
sub myapp {join _ => MyTest => appname($0), @_}

require_ok('YATT::Lite');

my $i = 1;
{
  my $yatt = new YATT::Lite(vfs => [data => {foo => 'bar'}]
			    , package => YATT::Lite->rootns_for(myapp($i))
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

# 次は YATT::Lite::Web::Dispatcher から make_connection して...

$i++;
require_ok('YATT::Lite::Web::DirHandler');
{
  
  my $yatt = new YATT::Lite::Web::DirHandler
    (rootname($0) . ".d"
     , package => YATT::Lite->rootns_for(myapp($i))
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
}
