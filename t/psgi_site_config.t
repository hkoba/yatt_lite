#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test::Kantan;

use YATT::t::t_preload; # To make Devel::Cover happy.
use YATT::Lite::WebMVC0::SiteApp;

use File::Temp qw/tempdir/;
use YATT::Lite::Util::File qw/mkfile/;
use YATT::Lite::Util qw/combination/;
use File::Path qw(make_path);
use Cwd;

use Plack::Request;
use Plack::Response;
use HTTP::Request::Common;
use HTTP::Message::PSGI;

use YATT::Lite::PSGIEnv;

my $TEMPDIR = tempdir(CLEANUP => 1);
my $CWD = cwd();
my $TESTNO = 0;
my $CT = ["Content-Type", q{text/html; charset="utf-8"}];

#========================================

describe "site_config", sub {

  my $make_dirs = sub {
    my $app_root = "$TEMPDIR/t" . ++$TESTNO;
    my $html_dir = "$app_root/html";

    make_path($html_dir);

    ($app_root, $html_dir);
  };

  my $make_siteapp = sub {
    my ($app_root, $html_dir, @args) = @_;

    my $site = YATT::Lite::WebMVC0::SiteApp
      ->new(app_ns => "Test$TESTNO"
            , app_root => $app_root
            , app_rootname => "$app_root/app"
            , doc_root => $html_dir
            , debug_cgen => $ENV{DEBUG}
            , @args
          );

    wantarray ? ($app_root, $html_dir, $site) : $site;
  };

  my @test_comb = combination(
    ['', 'app.'],
    ['xhf', 'yml'],
  );

  describe "&yatt:site_config();", sub {

    foreach my $test (@test_comb) {
      my ($prefix, $ext) = @$test;

      my $config_fn = $prefix."site_config.$ext";

      describe "read from $config_fn", sub {

        my ($app_root, $html_dir, $site) = $make_siteapp->($make_dirs->());

        MY->mkfile("$html_dir/index.yatt", <<'END');
app_name=&yatt:site_config(){app_name};
bar=&yatt:site_config(bar);
END

        MY->mkfile("$app_root/$config_fn", <<'END');
app_name: foo
bar: baz
END

        it "should get configs", sub {
          my Env $psgi = (GET "/")->to_psgi;

          expect($site->call($psgi))->to_be([200, $CT,
                                             ["app_name=foo\nbar=baz\n"]]);

        };

        # Update config.
        MY->mkfile("$app_root/$config_fn", <<'END');
app_name: FOO
bar: BAZ
END

        it "should get updated configs", sub {
          my Env $psgi = (GET "/")->to_psgi;

          expect($site->call($psgi))->to_be([200, $CT,
                                             ["app_name=FOO\nbar=BAZ\n"]]);

        };
      };
    }
  };

};

#========================================
chdir($CWD);

done_testing();
