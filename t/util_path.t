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

use autodie qw(mkdir chdir);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Test::More qw(no_plan);

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
  my $appdir = "$BASE/t$i";
  make_path(my $docroot = "$appdir/html"
	   , my $ytmpl = "$appdir/ytmpl");
  chdir($appdir);

  MY->mkfile("html/index.yatt", 'top');
  MY->mkfile("html/auth.yatt", 'auth');
  MY->mkfile("html/code.ydo", 'code');
  MY->mkfile("html/img/bg.png", 'background');
  MY->mkfile("html/d1/f1.yatt", 'in_d1');

  MY->mkfile("ytmpl/foo.yatt", "foo in tmpl");
  MY->mkfile("ytmpl/d1/f2.yatt", "f2 in tmpl");
  MY->mkfile("ytmpl/d2/bar.yatt", "bar in tmpl");

  my $test = sub {
    my ($part, $loc, $want, $longtitle) = @_;
    is_deeply [split_path("$appdir/$part$loc", $appdir, 1)], $want
      , "split_path: $loc";
  };

  my $res;
  $test->(html => "/auth.yatt"
	  , $res = [$docroot, "/", "auth.yatt", ""]);
  $test->(html => "/auth", $res);

  $test->(html => "/auth.yatt/foo"
	  , $res = [$docroot, "/", "auth.yatt", "/foo"]);
  $test->(html => "/auth/foo", $res);

  $test->(html => "/auth.yatt/foo/bar"
	  , $res = [$docroot, "/", "auth.yatt", "/foo/bar"]);
  $test->(html => "/auth/foo/bar", $res);

  $test->(ytmpl => "/foo.yatt"
	  , $res = [$ytmpl, "/", "foo.yatt", ""]);
  $test->(ytmpl => "/foo", $res);

  $test->(html => "/d1/f1.yatt"
	  , $res = [$docroot, "/d1/", "f1.yatt", ""]);
  $test->(html => "/d1/f1", $res);

  $test->(ytmpl => "/d1/f2.yatt"
	  , $res = [$ytmpl, "/d1/", "f2.yatt", ""]);
  $test->(ytmpl => "/d1/f2", $res);

  $test->(html => "/code.ydo"
	  , $res = [$docroot, '/', 'code.ydo', '']);

  $test->(html => "/img/bg.png"
	  , [$docroot, "/img/", "bg.png", ""]);

  $test->(html => "/img/missing.png"
	  , [$docroot, "/img/", "missing.png", ""]);
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
