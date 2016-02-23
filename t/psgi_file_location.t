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
use YATT::Lite::Util::File qw/mkfile/;
use File::Path qw(make_path);
use Cwd;

my $tempdir = tempdir(CLEANUP => 1);
my $testno = 0;
my $CT = ["Content-Type", q{text/html; charset="utf-8"}];

my $cwd = cwd();

{
  my $dir = "$tempdir/t" . ++$testno;
  make_path("$dir/html");
  my $site = YATT::Lite::WebMVC0::SiteApp
    ->new(app_ns => "Test$testno", app_root => $dir, doc_root => "$dir/html");

  foreach my $script_name ('', '/foo/bar') {

    describe "when script_name is '$script_name'", sub {
      my $item = 0;

      {
	my $wname = "test" . ++$item;
	my $url = "$script_name/$wname";
	MY->mkfile("$dir/html$script_name/$wname.yatt"
		   , qq{dir_location=&yatt:dir_location();});

	describe ":dir_location() in $script_name/$wname.yatt", sub {
	  my $psgi = (GET "$script_name/$wname")->to_psgi;
	  $psgi->{SCRIPT_NAME} = $script_name;

	  it "should return $script_name/", sub {
	    expect($site->call($psgi))->to_be([200, $CT, ["dir_location=$script_name/"]]);
	  };
	};
      }

      {
	my $wname = "test" . ++$item;
	my $url = "$script_name/$wname";
	MY->mkfile("$dir/html$script_name/$wname.yatt"
		   , qq{file_location=&yatt:file_location();});

	describe ":file_location() in $script_name/$wname.yatt", sub {
	  my $psgi = (GET "$script_name/$wname")->to_psgi;
	  $psgi->{SCRIPT_NAME} = $script_name;

	  it "should return $script_name/$wname", sub {
	    expect($site->call($psgi))->to_be([200, $CT, ["file_location=$script_name/$wname"]]);
	  };
	};
      }

      {
	my $wname = "test" . ++$item;
	my $url = "$script_name/$wname";
	MY->mkfile("$dir/html$script_name/$wname.yatt", <<'END');
<yatt:tab/>
<!yatt:page "/foo">
<yatt:tab/>
<!yatt:page "/bar">
<yatt:tab/>
<!yatt:widget tab>
&yatt:if(:is_current_page(),yes,no);
&yatt:if(:is_current_page(foo),yes,no);
&yatt:if(:is_current_page(bar),yes,no);
END

	my $test = sub {
	  my ($arg, $page, $to_be) = @_;
	  describe ":is_current_page($arg) for subpage='$page'", sub {
	    my $psgi = (GET "$script_name/$wname$page")->to_psgi;
	    $psgi->{SCRIPT_NAME} = $script_name;

	    it "should return (@$to_be)", sub {
	      expect([split " ", $site->call($psgi)->[2][0]])->to_be($to_be);
	    };
	  };
	};

	$test->("" => "" => [qw(yes no no)]);
	$test->(foo => "/foo" => [qw(no yes no)]);
	$test->(bar => "/bar" => [qw(no no yes)]);
      }

      {
	my $wname = "test" . ++$item;
	my $url = "$script_name/$wname";
	MY->mkfile("$dir/html$script_name/$wname.yatt", <<'END');
<yatt:tab/>
<!yatt:page "/foo">
<yatt:tab/>
<!yatt:page "/bar">
<yatt:tab/>
<!yatt:widget tab>
&yatt:if(:is_current_page(/),yes,no);
&yatt:if(:is_current_page(/foo),yes,no);
&yatt:if(:is_current_page(/bar),yes,no);
END

	my $test = sub {
	  my ($arg, $page, $to_be) = @_;
	  describe ":is_current_page($arg) for subpage='$page'", sub {
	    my $psgi = (GET "$script_name/$wname$page")->to_psgi;
	    $psgi->{SCRIPT_NAME} = $script_name;

	    it "should return (@$to_be)", sub {
	      expect([split " ", $site->call($psgi)->[2][0]])->to_be($to_be);
	    };
	  };
	};

	$test->("/" => "" => [qw(yes no no)]);
	$test->("/foo" => "/foo" => [qw(no yes no)]);
	$test->("/bar" => "/bar" => [qw(no no yes)]);
      }

    };
  }
}

chdir($cwd);

done_testing();
