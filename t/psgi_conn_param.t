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

my $app = YATT::Lite::WebMVC0::SiteApp
  ->new(  app_root => $FindBin::Bin
        , doc_root => "$rootname.d"
       )->to_app;

my $client = Plack::Test->create($app);
my $SUB;

sub test_ydo (&$;@) {
    my ( $subref, $request, %params ) = @_;
    $SUB = $subref;
    $client->request($request, %params);
}

sub TEST_IN_YDO { # called by xxx.ydo file.
    my ( $con ) = @_;
    $SUB->($con);
}


#
# TESTS
#

test_ydo {
    my ( $con ) = @_;
    isa_ok ( $con, "YATT::Lite::WebMVC0::Connection" );
} GET "/test.ydo?foo=bar";

test_ydo {
    my ( $con ) = @_;
    is ( $con->param('foo'), 'bar', "param('foo')" );
} GET "/test.ydo?foo=bar";

test_ydo {
    my ( $con ) = @_;
    is( $con->raw_body, 'yatt ansin! utyuryokou', "raw_body" );
} POST "/test.ydo", Content => 'yatt ansin! utyuryokou';

test_ydo {
    my ( $con ) = @_;
    is( $con->param('foo'), 'bar', "param with query path" );
    is( $con->raw_body, 'yatt ansin! utyuryokou', "raw_body with query path" );
} POST "/test.ydo?foo=bar", Content => 'yatt ansin! utyuryokou';


done_testing();
