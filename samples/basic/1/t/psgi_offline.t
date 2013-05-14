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
use Cwd ();
my ($app_root, @libdir);
BEGIN {
  if (-r __FILE__) {
    # detect where app.psgi is placed.
    $app_root = dirname(dirname(File::Spec->rel2abs(__FILE__)));
  } else {
    # older uwsgi do not set __FILE__ correctly, so use cwd instead.
    $app_root = Cwd::cwd();
  }
  my $dn;
  if (-d (($dn = "$app_root/lib") . "/YATT")) {
    push @libdir, $dn
  } elsif (($dn) = $app_root =~ m{^(.*?/)YATT/}) {
    push @libdir, $dn;
  }
}
use lib @libdir;
#----------------------------------------

use Test::More;

BEGIN {
  foreach my $req (qw(Plack::Test)) {
    unless (eval qq{require $req}) {
      plan(skip_all => "$req is not installed."); exit;
    }
  }
}

use Plack::Test;
use Plack::Util;

use YATT::Lite::Breakpoint;
# use YATT::Lite::Util qw(ostream);
use YATT::Lite::Test::XHFTest2;
use base qw(YATT::Lite::Test::XHFTest2);
use YATT::t::t_preload; # To make Devel::Cover happy.

my MY $tests = MY->load_tests([dir => "$FindBin::Bin/../html"]
			      , @ARGV ? @ARGV : $FindBin::Bin);
$tests->enter;

plan $tests->test_plan(1);

use Cwd;
$ENV{YATT_DOCUMENT_ROOT} = cwd;
ok(my $app = Plack::Util::load_psgi("$FindBin::Bin/../app.psgi"), "load_psgi");

test_psgi $app, sub {
  my ($cb) = shift;
  foreach my File $sect (@{$tests->{files}}) {
    my $dir = $tests->{cf_dir};
    my $sect_name = $tests->file_title($sect);
    foreach my Item $item (@{$sect->{items}}) {
    SKIP: {
	if ($item->{cf_PERL_MINVER} and $] < $item->{cf_PERL_MINVER}) {
	  Test::More::skip "by perl-$] < PERL_MINVER($item->{cf_PERL_MINVER}) $sect_name", 1;
	}

	if ($item->{cf_BREAK}) {
	  YATT::Lite::Breakpoint::breakpoint();
	}

	if (my $action = $item->{cf_ACTION}) {
	  my ($method, @args) = @$action;
	  my $sub = $tests->can("action_$method")
	    or die "No such action: $method";
	  $sub->($tests, @args);
	  next;
	}

	$item->{cf_METHOD} //= 'GET';
	my $T = defined $item->{cf_TITLE} ? "[$item->{cf_TITLE}]" : '';

	my $res = $tests->run_psgicb($cb, $item);

	if ($item->{cf_ERROR}) {
	  (my $str = $res->content) =~ s/^Internal Server error\n//;
	  like $str, qr{$item->{cf_ERROR}}
	    , "[$sect_name] $T ERROR $item->{cf_METHOD} $item->{cf_FILE}";
	  next;
	} elsif ($res->code >= 300 && $res->code < 500) {
	  # fall through
	} elsif ($res->code != 200) {
	  Test::More::fail $item->{cf_FILE};
	  Test::More::diag $res->content;
	  next;
	}

	if ($item->{cf_METHOD} eq 'POST' and $item->{cf_HEADER}) {
	  my @header = @{$item->{cf_HEADER}};
	  while (my ($f, $v) = splice @header, 0, 2) {
	    my $name = "[$sect_name] $T POST $item->{cf_FILE} $f";
	    my $got = $res->header($f);
	    if (defined $got) {
	      like $got, qr/$v/, $name;
	    } else {
	      fail $name; diag("Header '$f' was undef");
	    }
	  }
	} elsif (ref $item->{cf_BODY}) {
	  like nocr($res->content), $tests->mkseqpat($item->{cf_BODY})
	    , "[$sect_name] $T $item->{cf_METHOD} $item->{cf_FILE}";
	} else {
	  eq_or_diff trimlast(nocr($res->content)), $item->{cf_BODY}
	    , "[$sect_name] $T $item->{cf_METHOD} $item->{cf_FILE}";
	}
      }
    }
  }
};

sub base_url {
  shift; "http://localhost/";
}
