#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test::Kantan;
use File::Temp qw/tempdir/;

use Plack::Request;
use Plack::Response;
use HTTP::Request::Common;
use HTTP::Message::PSGI;

use YATT::t::t_preload; # To make Devel::Cover happy.
use YATT::Lite::WebMVC0::SiteApp;
use YATT::Lite::Util qw/combination/;
use YATT::Lite::Util::File qw/mkfile/;
use File::Path qw(make_path);
use Cwd;

use YATT::Lite::PSGIEnv;

my $TEMPDIR = tempdir(CLEANUP => 1);
my $CWD = cwd();
my $TESTNO = 0;
my $CT = ["Content-Type", q{text/html; charset="utf-8"}];

my $TODO = $ENV{TEST_TODO};

#----------------------------------------

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
          , doc_root => $html_dir
          , debug_cgen => $ENV{DEBUG}
        );

  wantarray ? ($app_root, $html_dir, $site) : $site;
};

my $with_or_without = sub {$_[0] ? "With" : "Without"};

#========================================

foreach my $has_index (1, 0) {

  describe $with_or_without->($has_index)." index.yatt", sub {

    describe "action.ydo", sub {
      my ($app_root, $html_dir, $site) = $make_siteapp->($make_dirs->());

      MY->mkfile("$html_dir/index.yatt", <<'END') if $has_index;
<h2>Hello</h2>

<!yatt:action "/foo">
# should not be called (hidden by foo.ydo)
print $CON "action foo in index.yatt";

<!yatt:action "/bar">
print $CON "action bar in index.yatt";
END

      MY->mkfile("$html_dir/foo.ydo", <<'END');
use strict;
return sub {
  my ($this, $CON) = @_;
  print $CON "action in foo.ydo";
};
END

      describe "request /foo.ydo", sub {
        my Env $psgi = (GET "/foo.ydo")->to_psgi;

        it "should invoke action in foo.ydo", sub {
          expect($site->call($psgi))->to_be([200, $CT, ["action in foo.ydo"]]);
        };
      };

      # TODO:
      if ($TODO) {
        describe "request /foo", sub {
          my Env $psgi = (GET "/foo")->to_psgi;

          it "should invoke action in foo.ydo", sub {
            expect($site->call($psgi))->to_be([200, $CT, ["action in foo.ydo"]]);
          };
        };
      }

      if ($has_index) {
        describe "request /bar (for sanity check)", sub {
          my Env $psgi = (GET "/bar")->to_psgi;

          it "should invoke action bar in index.yatt", sub {
            expect($site->call($psgi))->to_be([200, $CT, ["action bar in index.yatt"]]);
          };
        };
      }
    };

    describe "Action in .htyattrc.pl", sub {
      my ($app_root, $html_dir) = $make_dirs->();

      make_path(my $tmpl_dir = "$app_root/ytmpl");

      MY->mkfile("$html_dir/index.yatt", <<'END') if $has_index;
<h2>Hello</h2>

<!yatt:page "/bar">
page bar in index.yatt
END

      # .htyattrc.pl should be created BEFORE siteapp->new.
      MY->mkfile("$html_dir/.htyattrc.pl", <<'END');
use strict;

use YATT::Lite qw/Action/;

Action foo => sub {
  my ($this, $CON) = @_;
  print $CON "action foo in .htyattrc.pl";
};

END

      my $site = $make_siteapp->($app_root, $html_dir, app_base => '@ytmpl');

      if ($has_index or $TODO) {
        describe "request /?!foo=1", sub {
          my Env $psgi = (GET "/?!foo=1")->to_psgi;

          it "should invoke action foo in .htyattrc.pl", sub {
            expect($site->call($psgi))->to_be([200, $CT, ["action foo in .htyattrc.pl"]]);
          };
        };
      }

      if ($TODO) {
        describe "request /foo", sub {
          my Env $psgi = (GET "/foo")->to_psgi;

          it "should invoke action foo in .htyattrc.pl", sub {
            expect($site->call($psgi))->to_be([200, $CT, ["action foo in .htyattrc.pl"]]);
          };
        };
      }
    };

    ($has_index or $TODO)
      and
    describe "site->mount_action(URL, subref)", sub {
      my ($app_root, $html_dir) = $make_dirs->();

      make_path($html_dir);

      MY->mkfile("$html_dir/index.yatt", <<'END') if $has_index;
<h2>Hello</h2>

<!yatt:page "/bar">
page bar in index.yatt
END

      my $site = $make_siteapp->($app_root, $html_dir, app_base => '@ytmpl');

      $site->mount_action(
        '/foo',
        sub {
          my ($this, $con) = @_;
          print $con "action foo from mount_action";
        }
      );

      if ($TODO) {
        describe "request /?!foo=1", sub {
          my Env $psgi = (GET "/?!foo=1")->to_psgi;

          it "should invoke action foo from mount_action", sub {
            expect($site->call($psgi))->to_be([200, $CT, ["action foo from mount_action"]]);
          };
        };
      }

      describe "request /foo", sub {
        my Env $psgi = (GET "/foo")->to_psgi;

        it "should invoke action foo from mount_action", sub {
          expect($site->call($psgi))->to_be([200, $CT, ["action foo from mount_action"]]);
        };
      };
    };
  };
}

#========================================
chdir($CWD);

done_testing();

