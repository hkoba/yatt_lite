#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings FATAL => qw(all);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test::More;
use YATT::t::t_preload; # To make Devel::Cover happy.
use YATT::Lite::WebMVC0::SiteApp;


BEGIN {
  foreach my $req (qw(Plack Plack::Test Plack::Response HTTP::Request::Common)) {
    unless (eval qq{require $req;}) {
      plan skip_all => "$req is not installed."; exit;
    }
    $req->import;
  }
}

my $rootname = untaint_any($FindBin::Bin."/psgi");

my $site = YATT::Lite::WebMVC0::SiteApp
  ->new(  app_root => $FindBin::Bin
        , doc_root => "$rootname.d"
       );
my $app = $site->to_app;

my $client = Plack::Test->create($app);

sub test_action (&$;@) {
    my ( $subref, $request, %params ) = @_;

    $site->mount_action($request->uri->path, $subref);

    $client->request($request, %params);
}

#
# TESTS
#

test_action {
    my ( $this, $con ) = @_;
    isa_ok ( $con, "YATT::Lite::WebMVC0::Connection" );
} GET "/test?foo=bar";

test_action {
    my ( $this, $con ) = @_;
    is ( $con->param('foo'), 'bar', "param('foo')" );
} GET "/test?foo=bar";

test_action {
    my ( $this, $con ) = @_;
    is( $con->raw_body, 'yatt ansin! utyuryokou', "raw_body" );
} POST "/test", Content => 'yatt ansin! utyuryokou';

test_action {
    my ( $this, $con ) = @_;
    is( $con->param('foo'), 'bar', "param with query path" );
    is( $con->raw_body, 'yatt ansin! utyuryokou', "raw_body with query path" );
} POST "/test?foo=bar", Content => 'yatt ansin! utyuryokou';


done_testing();
