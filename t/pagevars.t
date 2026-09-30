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
    #!/usr/bin/env perl
    package pagevars;
    use YATT::Lite::PageConsts -as_base, qw(as_html);

    my @common = (cmn => "CMN");

    my %PAGES;
    $PAGES{index} = +{
      foo => "FOO",
      bar => "BARRR",
      @common,
    };
    $PAGES{uselayout} = +{
      qux => "QUX",
    };
    $PAGES{'sub/another'} = +{
      baz => "BAZZZ",
      qux => as_html("foo<b>bar</b>baz"),
    };

    MY->define_pages(%PAGES);
    MY->cli_run(\@ARGV) unless caller;
    1;
END

      MY->mkfile_may_wait("$dir/public/index.yatt", <<'END');
&yatt:foo; &yatt:bar;
END

      MY->mkfile_may_wait("$dir/public/sub/another.yatt", <<'END');
&yatt:baz; &yatt:qux;
END

      MY->mkfile_may_wait("$dir/public/uselayout.yatt", <<'END');
&yatt:qux;<yatt:layout/>
END

      # Templates in ytmpl/ are not pages (page_name is undef),
      # so pagevars must not be applied to them.
      MY->mkfile_may_wait("$dir/ytmpl/layout.ytmpl", <<'END');
(dummy)
END

  }

  my $site = YATT::Lite::WebMVC0::SiteApp->new(
    app_ns => "Test$testno",
    app_root => $dir,
    doc_root => "$dir/public",
    app_base => '@ytmpl',
    pagevars => 'pagevars',
    debug_cgen => $ENV{DEBUG_CGEN},
  );


  is($site->render("index"), "FOO BARRR\n", q{pagevar index});

  is($site->render("sub/another"), "BAZZZ foo<b>bar</b>baz\n", q{pagevar sub/another});

  is(eval {$site->render("uselayout")} // "ERROR: $@", "QUX(dummy)\n\n"
     , "page using a widget from ytmpl (non-page template)");

  {
    my $site2 = YATT::Lite::WebMVC0::SiteApp->new(
      app_ns => "Test${testno}b",
      app_root => $dir,
      doc_root => "$dir/public",
      app_base => '@ytmpl',
      pagevars => 'pagevars',
    );

    # Inspector and Walker load directories without $basedir.
    # page_prefix must not depend on which path loaded the directory first.
    $site2->load_yatt("$dir/public/sub");

    is(eval {$site2->render("sub/another")} // "ERROR: $@"
       , "BAZZZ foo<b>bar</b>baz\n"
       , "pagevar sub/another, directory loaded without basedir");
  }

  #========================================
  # const_type: value -> yatt variable type

  is([map {pagevars->const_type($_)}
      "str", 3, [1], {a => 1}, sub {}, pagevars::as_html("<b>")]
     , [qw(text text list scalar code html)]
     , "const_type");

  #========================================
  # locate_const: where a constant is defined (file, 1-based line)

  {
    my $pm = "$dir/lib/pagevars.pm";
    my $line_of = do {
      my @lines = do {open my $fh, '<', $pm or die "$pm: $!"; <$fh>};
      sub {
        my ($re) = @_;
        my ($i) = grep {$lines[$_] =~ $re} 0 .. $#lines;
        defined $i ? $i+1 : undef;
      };
    };

    is([pagevars->locate_const(index => 'bar')]
       , [$pm, $line_of->(qr/^\s*bar =>/)]
       , "locate_const: key in the page block");

    is([pagevars->locate_const('sub/another' => 'qux')]
       , [$pm, $line_of->(qr/^\s*qux => as_html/)]
       , "locate_const: same name in another page is not confused");

    is([pagevars->locate_const(uselayout => 'qux')]
       , [$pm, $line_of->(qr/^\s*qux => "QUX"/)]
       , "locate_const: same name, the other page");

    is([pagevars->locate_const(index => 'cmn')]
       , [$pm, $line_of->(qr/my \@common/)]
       , "locate_const: common value defined outside of the page block");

    is([pagevars->locate_const(index => 'nosuch')], []
       , "locate_const: no such constant");
  }
}

done_testing;
