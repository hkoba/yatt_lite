#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);

use 5.010;

sub untaint_any {$_[0] =~ m{(.*)} and $1}
use File::Basename;
use File::Spec;
my ($bindir, $libdir);
use lib untaint_any
  (File::Spec->rel2abs
   ($libdir = ($bindir = dirname(untaint_any($0)))
    . "/../../../../runyatt.lib"));

sub MY () {__PACKAGE__}
use base qw(YATT::Lite::XHFTest2);
use YATT::Lite::Util qw(lexpand);
use YATT::Lite::TestFCGI;

use YATT::Lite::Breakpoint;
use YATT::Lite::XHFTest2;

my $CLASS = YATT::Lite::TestFCGI::Auto->class
  or YATT::Lite::TestFCGI::Auto->skip_all
  ('None of FCGI::Client and /usr/bin/cgi-fcgi is available');

unless (eval {require Test::Differences}) {
  $CLASS->skip_all('Test::Differences is not installed');
}

my $mech = $CLASS->new
  (map {
    (rootdir => $_
     , fcgiscript => "$_/cgi-bin/runyatt.fcgi")
  } File::Spec->rel2abs("$bindir/.."));

if (my $reason = $mech->check_skip_reason) {
  $mech->skip_all($reason);
}

my MY $tests = MY->load_tests([dir => "$bindir/.."
			       , libdir => untaint_any
			       (File::Spec->rel2abs($libdir))]
			      , @ARGV ? @ARGV : $bindir);
$tests->enter;

my @plan = $tests->test_plan;
# skip_all should be called before fork.
if (@plan and $plan[0] eq 'skip_all') {
  $mech->plan(@plan);
}

$mech->fork_server;

# test plan should be configured after fork.
$mech->plan(@plan);

$tests->mechanized($mech);

sub base_url { shift; '/'; }

sub ntests_per_item {
  (my MY $tests, my Item $item) = @_;
  lexpand($item->{cf_HEADER})/2
    + (($item->{cf_BODY} || $item->{cf_ERROR}) ? 1 : 0);
}

sub mech_request {
  (my MY $tests, my $mech, my Item $item) = @_;
  my $method = $tests->item_method($item);
  my $url = $tests->item_url_file($item);
  $mech->request($method, $url, $item->{cf_PARAM});
}

# Local Variables: #
# coding: utf-8 #
# End: #
