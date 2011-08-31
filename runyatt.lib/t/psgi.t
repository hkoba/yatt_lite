#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use Test::More;

sub rootname { my $fn = shift; $fn =~ s/\.\w+$//; join "", $fn, @_ }
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use FindBin;
use lib untaint_any("$FindBin::Bin/..");
use YATT::Lite::TestUtil;
use YATT::Lite::Breakpoint;

BEGIN {
  # Because use YATT::Lite::DBSchema::DBIC loads DBIx::Class::Schema.
  foreach my $req (qw(Plack)) {
    unless (eval qq{require $req}) {
      plan skip_all => "$req is not installed."; exit;
    }
  }
}

use HTTP::Request::Common;
use Plack::Test;
use YATT::Lite::Web::Dispatcher;

my $rootname = untaint_any($FindBin::Bin."/".rootname($FindBin::RealScript));

plan qw(no_plan);

sub is_or_like($$;$) {
  my ($got, $expect, $title) = @_;
  if (ref $expect) {
    like $got, $expect, $title;
  } else {
    is $got, $expect, $title;
  }
}

{
  my $app = YATT::Lite::Web::Dispatcher
    ->new(document_root => "$rootname.d"
	  , tmpldirs => ["$rootname.ytmpl"]
	  , basens => 'MyApp'
	  , namespace => ['yatt', 'perl', 'js']
	  , header_charset => 'utf-8')->to_app;

  my $hello = sub {
    my ($id, $body) = @_;
    <<END;
<div id="$id">
  Hello $body!
</div>

END
  };

  my $out_index = $hello->(content => 'World');
  my $out_beta = $hello->(beta => "world line");

  # XXX: subdir
  # XXX: .htyattrc.pl and entity
  #
  test_psgi $app, sub {
    my ($cb) = @_;
    foreach my $test
      (["/", 200, $out_index, ["Content-type", qq{text/html; charset="utf-8"}]]
       , ["/index", 200, $out_index]
       , ["/index.yatt", 200, $out_index]
       , ["/index.yatt/foo/bar", 200, $out_index]
       , ["/test.lib/Foo.pm", 403, qr{Forbidden}]
       , ["/.htaccess", 403, qr{Forbidden}]
       , ["/hidden.ytmpl", 403, qr{Forbidden}]
       , ["/beta/world_line", 200, $out_beta]
       , ["/beta/world_line.yatt", 200, $out_beta]
       , ["/beta/world_line.yatt/baz", 200, $out_beta]
      ) {
      my ($path, $code, $body, $header) = @$test;
      my $res = $cb->(GET $path);
      is $res->code, $code, "[code] $path";
      is_or_like $res->content, $body, "[body] $path";
      if ($header and my @h = @$header) {
	while (my ($key, $value) = splice @h, 0, 2) {
	  is_or_like $res->header($key), $value, "[header][$key] $path";
	}
      }
    }
  };
}
