#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }

use Test::More;
use File::Temp qw(tempdir);

use Plack::Test;
use HTTP::Request::Common;

use YATT::Lite::Breakpoint;

use YATT::t::t_preload; # To make Devel::Cover happy.
use YATT::Lite::Util::File qw(mkfile);

use YATT::Lite::WebMVC0::SiteApp ();

my $TMP = tempdir(CLEANUP => $ENV{NO_CLEANUP} ? 0 : 1);
END {
  chdir('/');
}

my $i = 1;
{
  my $CLS = 'MyAppUnknownParams';
  my $approot = "$TMP/app$i";
  my $docroot = "$approot/docs";
  MY->mkfile("$docroot/index.yatt", <<'END');
<!yatt:args x y z>
x=&yatt:x;
y=&yatt:y;
z=&yatt:z;
stash=&yatt:CON:stash();
<yatt:body/>
END

  local $ENV{PLACK_ENV} = 'deployment';

  my $site = YATT::Lite::WebMVC0::SiteApp->new(
    app_ns => $CLS
    , app_root => $approot
    , doc_root => $docroot
    # , stash_unknown_params_to => 'yatt.unknown_params'
  );

  test_psgi $site->to_app, sub {
    my ($cb) = @_;
    # Sanity check.
    my $res = $cb->(GET "/?x=A;y=B;z=C");
    is $res->content, "x=A\ny=B\nz=C\nstash={'yatt.unknown_params' => {}}\n\n";

    # Unknown params are stashed.
    $res = $cb->(GET "/?a=X;b=Y;x=Z");
    is $res->content, "x=Z\ny=\nz=\nstash={'yatt.unknown_params' => {'a' => ['X'],'b' => ['Y']}}\n\n";

    # Also known but code params are stashed.
    $res = $cb->(GET "/?body=foo");
    is $res->content, "x=\ny=\nz=\nstash={'yatt.unknown_params' => {'body' => ['foo']}}\n\n";

  };
}

++$i;
{
  my $CLS = 'MyAppInDevelopment';
  my $approot = "$TMP/app$i";
  my $docroot = "$approot/docs";
  MY->mkfile("$docroot/index.yatt", <<'END');
<!yatt:args x y z>
x=&yatt:x;
y=&yatt:y;
z=&yatt:z;
stash=&yatt:CON:stash();
<yatt:body/>
END

  local $ENV{PLACK_ENV} = 'development';

  my $site = YATT::Lite::WebMVC0::SiteApp->new(
    app_ns => $CLS
    , app_root => $approot
    , doc_root => $docroot
  );

  test_psgi $site->to_app, sub {
    my ($cb) = @_;
    # Sanity check.
    my $res = $cb->(GET "/?x=A;y=B;z=C");
    is $res->content, "x=A\ny=B\nz=C\nstash={}\n\n";

    # Unknown args are raised as error
    $res = $cb->(GET "/?a=A;y=B;z=C");
    is $res->code, 500;
    like $res->content, qr/Unknown args: a/;
  }
}

done_testing();
