#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test2::V0 -no_srand;
use File::Temp qw/tempdir/;

use YATT::t::t_preload; # To make Devel::Cover happy.
use YATT::Lite::WebMVC0::SiteApp;
use YATT::Lite::Util::File qw/mkfile_may_wait/;

my $tempdir = tempdir(CLEANUP => 1);
my $testno = 0;

{
  my $dir = "$tempdir/t" . ++$testno;

  #========================================

  {
    require lib;
    lib->import("$dir/lib");

    MY->mkfile_may_wait("$dir/lib/pagevars.pm", <<'END');
    package pagevars;
    use YATT::Lite::PageConsts;

    my %PAGES;
    $PAGES{index} = +{
      foo => "FOO",
      bar => "BARRR",
    };
    $PAGES{'sub/another'} = +{
      baz => "BAZZZ",
      # baz => YATT::Util::VarExporter::as_html("foo<b>bar</b>baz")
    };

    YATT::Lite::PageConsts->define_pages(%PAGES);
    1;
END

      MY->mkfile_may_wait("$dir/public/index.yatt", <<'END');
&yatt:foo; &yatt:bar;
END

  }

  my $site = YATT::Lite::WebMVC0::SiteApp->new(
    app_ns => "Test$testno",
    app_root => $dir,
    doc_root => "$dir/public",
    pagevars => 'pagevars',
    debug_cgen => $ENV{DEBUG_CGEN},
  );


  is($site->render("index"), "FOO BARRR\n");

}

done_testing;
