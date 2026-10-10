#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#
# <yatt:my var>...</yatt:my> などで出力を捕捉している間の $CON。
#
#  - 捕捉中の widget/body 呼び出しの出力は、変数に入る (GH-293)
#  - 捕捉中の $CON は素の fh なので、$CON のメソッドは呼べない (GH-295, TODO)
#
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test::More;
use File::Temp qw/tempdir/;

use YATT::t::t_preload; # To make Devel::Cover happy.
use YATT::Lite::WebMVC0::SiteApp;
use YATT::Lite::Util::File qw/mkfile_may_wait/;

my $tempdir = tempdir(CLEANUP => 1);
END {chdir "/"}
my $testno = 0;

my $make_app = sub {
  my (%files) = @_;
  my $app_root = "$tempdir/t" . ++$testno;
  my $docroot = "$app_root/docs";
  YATT::Lite::Util::File->mkfile_may_wait(
    map {("$docroot/$_" => $files{$_})} keys %files
  );
  YATT::Lite::WebMVC0::SiteApp->new(
    app_ns => "TestCaptureCon$testno",
    app_root => $app_root,
    doc_root => $docroot,
  );
};

{
  my $site = $make_app->(
    'body.yatt' => <<'END',
<yatt:foo>[body]</yatt:foo>

<!yatt:widget foo body=[code]>
<yatt:my tmp>(&yatt:body();)</yatt:my>
{&yatt:tmp;}
END
    'conmethod.yatt' => <<'END',
<yatt:my tmp>(<yatt:foo/>)</yatt:my>
{&yatt:tmp;}

<!yatt:widget foo>
&yatt:CON:file();
END
  );

  is(eval {$site->render("body")} // "ERROR: $@", "{([body])}\n\n"
     , "body output is captured into my var");

  TODO: {
    local $TODO = "GH-295: captured \$CON is a bare filehandle";
    like(eval {$site->render("conmethod")} // "ERROR: $@"
         , qr{^\{\(\S*conmethod\.yatt}
         , "\$CON methods are available while capturing");
  }
}

done_testing();
