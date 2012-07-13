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

use Test::More;
use YATT::Lite::Test::TestUtil;
use YATT::Lite::Breakpoint;
use YATT::t::t_preload; # To make Devel::Cover happy.

sub rootname { my $fn = shift; $fn =~ s/\.\w+$//; join "", $fn, @_ }

BEGIN {
  # Because use YATT::Lite::DBSchema::DBIC loads DBIx::Class::Schema.
  foreach my $req (qw(Plack)) {
    unless (eval qq{require $req}) {
      plan skip_all => "$req is not installed."; exit;
    }
  }
}

use HTTP::Request::Common;
use YATT::Lite::WebMVC0::SiteApp;
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
  my $app = YATT::Lite::WebMVC0::SiteApp
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

{
  {
    package MyBackend1; sub MY () {__PACKAGE__}
    use base qw/YATT::Lite::Object/;
    use fields qw/base_path
		  paths
		  cf_name/;
    sub startup {
      (my MY $self, my $router, my @apps) = @_;
      my $docs = $self->{base_path} = $router->cget('doc_root');
      $docs =~ s,/+$,,;
      foreach my $app (@apps) {
	my $dir = $app->cget('dir');
	$dir =~ s/^\Q$docs\E//;
	push @{$self->{paths}}, $dir;
      }
    }

    sub paths {
      (my MY $self) = @_;
      sort @{$self->{paths}}
    }
  }
  my $backend = MyBackend1->new(name => 'backend test');
  my $app = YATT::Lite::WebMVC0::SiteApp
    ->new(app_root => $FindBin::Bin
	  , doc_root => "$rootname.d"
	  , app_ns => 'MyApp2'
	  , backend => $backend
	 )
      ->to_app;

  is_deeply [$backend->paths]
    , ['', qw|/beta /test.lib|]
    , "backend startup is called";
}

