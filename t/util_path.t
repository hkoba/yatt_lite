#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}

use autodie qw(mkdir chdir);
use File::Temp qw(tempdir);
use Test::More qw(no_plan);

use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/lib");

use YATT::Lite::Util::File qw(mkfile);

BEGIN {
  use_ok('YATT::Lite::Util', qw(split_path lookup_path));
}

my $BASE = tempdir(CLEANUP => $ENV{NO_CLEANUP} ? 0 : 1);
END {
  chdir('/');
}

my $i = 1;
{
  mkdir(my $realdir = "$BASE/t$i.docs");
  chdir($realdir);

  MY->mkfile("index.yatt", 'top');
  MY->mkfile("auth.yatt", 'auth');
  MY->mkfile("code.ydo", 'code');
  MY->mkfile("img/bg.png", 'background');
  MY->mkfile("d1/f1.yatt", 'in_d1');

  my $test = sub {
    my ($loc, $want, $longtitle) = @_;
    is_deeply [split_path("$realdir$loc", $realdir)], $want
      , "split_path: $loc";
  };

  my $res;
  $test->("/auth.yatt"
	  , $res = [$realdir, "/", "auth.yatt", ""]);
  $test->("/auth", $res);

  $test->("/auth.yatt/foo"
	  , $res = [$realdir, "/", "auth.yatt", "/foo"]);
  $test->("/auth/foo", $res);

  $test->("/auth.yatt/foo/bar"
	  , $res = [$realdir, "/", "auth.yatt", "/foo/bar"]);
  $test->("/auth/foo/bar", $res);

  $test->("/code.ydo"
	  , $res = [$realdir, '/', 'code.ydo', '']);

  $test->("/img/bg.png"
	  , [$realdir, "/img/", "bg.png", ""]);

  $test->("/img/missing.png"
	  , [$realdir, "/img/", "missing.png", ""]);
}

$i++;
{
  mkdir(my $realdir = "$BASE/t$i.docs");
  chdir($realdir);

  my $html = "$realdir/html";
  MY->mkfile("$html/test.yatt", 'test1');
  MY->mkfile("$html/real/index.yatt", 'index in realsub');
  MY->mkfile("$html/real/test.yatt", 'test in realsub');
  MY->mkfile("$html/real/code.ydo", 'code in realsub');
  MY->mkfile("$html/rootcode.ydo", 'rootcode');

  my $tmpl = "$realdir/runyatt.ytmpl";
  MY->mkfile("$tmpl/index.yatt", 'virtual index');
  MY->mkfile("$tmpl/virt/index.yatt", 'virtual index in virt');
  MY->mkfile("$tmpl/virt/test.yatt", 'test in virt');
  MY->mkfile("$tmpl/virt/code.ydo", 'code in virt');
  MY->mkfile("$tmpl/virtcode.ydo", 'virtcode');

  my @tmpls = map {"$realdir/$_"} qw(html runyatt.ytmpl);
  my $test = sub {
    my ($loc, $want, @rest) = @_;
    is_deeply [lookup_path($loc, \@tmpls, @rest)]
      , $want, "lookup_path: $loc";
  };

  my $res;
  $test->("/index.yatt"
	  , $res = [$tmpl, '/', 'index.yatt', '']);
  $test->("/index", $res);
  $test->("/", $res);

  $test->("/index.yatt/foo/bar"
	  , $res = [$tmpl, '/', 'index.yatt', '/foo/bar']);
  $test->("/index/foo/bar", $res);

  $test->("/test.yatt"
	  , $res = [$html, '/', 'test.yatt', '']);
  $test->("/test", $res);

  $test->("/test.yatt/foo/bar"
	  , $res = [$html, '/', 'test.yatt', '/foo/bar']);
  $test->("/test/foo/bar", $res);

  $test->("/real/index.yatt"
	  , $res = [$html, '/real/', 'index.yatt', '']);
  $test->("/real/index", $res);
  $test->("/real/", $res);

  $test->("/real/index.yatt/foo/bar"
	  , $res = [$html, '/real/', 'index.yatt', '/foo/bar']);
  $test->("/real/index/foo/bar", $res);

  $test->("/real/test.yatt"
	  , $res = [$html, '/real/', 'test.yatt', '']);
  $test->("/real/test", $res);

  $test->("/real/code.ydo"
	  , $res = [$html, '/real/', 'code.ydo', '']);
  $test->("/rootcode.ydo"
	  , $res = [$html, '/', 'rootcode.ydo', '']);
  $test->("/virt/code.ydo"
	  , $res = [$tmpl, '/virt/', 'code.ydo', '']);
  $test->("/virtcode.ydo"
	  , $res = [$tmpl, '/', 'virtcode.ydo', '']);

  $test->("/virt/index.yatt"
	  , $res = [$tmpl, '/virt/', 'index.yatt', '']);
  $test->("/virt/index", $res);
  $test->("/virt/", $res);
  $test->("/virt/index.yatt/foo/bar"
	  , $res = [$tmpl, '/virt/', 'index.yatt', '/foo/bar']);
  $test->("/virt/index/foo/bar", $res);

  $test->("/virt/test.yatt"
	  , $res = [$tmpl, '/virt/', 'test.yatt', '']);
  $test->("/virt/test", $res);

  $test->("/virt/test.yatt/foo/bar"
	  , $res = [$tmpl, '/virt/', 'test.yatt', '/foo/bar']);
  $test->("/virt/test/foo/bar", $res);
}
