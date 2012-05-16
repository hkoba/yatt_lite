#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use Test::More;

sub rootname { my $fn = shift; $fn =~ s/\.\w+$//; join "", $fn, @_ }
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use FindBin;
use lib untaint_any("$FindBin::Bin/lib");
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
use YATT::Lite::WebMVC0;
use YATT::Lite::PSGIEnv;

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
  my $app = YATT::Lite::WebMVC0
    ->new(app_root => $FindBin::Bin
	  , doc_root => "$rootname.d"
	  , app_ns => 'MyApp'
	  , app_base => ['@psgi.ytmpl']
	  , namespace => ['yatt', 'perl', 'js']
	  , header_charset => 'utf-8')
      ->to_app;

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
  foreach my $test
    (["/", 200, $out_index, ["Content-Type", qq{text/html; charset="utf-8"}]]
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
    my $tuple = do {
      my Env $env = Env->psgi_simple_env;
      $env->{PATH_INFO} = $path;
      $app->($env);
    };
    is $tuple->[0], $code, "[code] $path";
    is_or_like join("", @{$tuple->[2]}), $body, "[body] $path";
    if ($header and my @h = @$header) {
      my %header = @{$tuple->[1]};
      while (my ($key, $value) = splice @h, 0, 2) {
	is_or_like $header{$key}, $value, "[header][$key] $path";
      }
    }
  }
}
