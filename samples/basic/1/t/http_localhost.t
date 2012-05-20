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
    $app_root = File::Basename::dirname(File::Spec->rel2abs(__FILE__));
  } else {
    # older uwsgi do not set __FILE__ correctly, so use cwd instead.
    $app_root = Cwd::cwd();
  }
  if (-d (my $dn = "$app_root/lib")) {
    push @libdir, $dn
  } elsif (my ($found) = $app_root =~ m{^(.*?/)YATT/}) {
    push @libdir, $found;
  }
}
use lib @libdir;
#----------------------------------------
use 5.010;

use YATT::Lite::Breakpoint;
use YATT::Lite::Test::XHFTest2;
use base qw(YATT::Lite::Test::XHFTest2);
use fields qw(base_url);
use YATT::Lite::Util qw(lexpand);

my MY $tests = MY->load_tests([dir => "$FindBin::Bin/../html"]
			      , @ARGV ? @ARGV : $FindBin::Bin);
$tests->enter;

plan $tests->test_plan;

$tests->mechanized(new WWW::Mechanize(max_redirect => 0));

sub test_plan {
  my MY $tests = shift;
  unless (eval {require WWW::Mechanize}) {
    return skip_all => 'WWW::Mechanize is not installed';
  }

  unless (-d "cgi-bin" and grep {-x "cgi-bin/runyatt.$_"} qw(cgi fcgi)) {
    return skip_all => "Can't find cgi-bin/runyatt.cgi";
  }

  unless (-r ".htaccess") {
    return skip_all => "Can't find .htaccess";
  }

  unless (my $cgi_url = $tests->find_yatt_handler('.htaccess')) {
    return skip_all => "Can't find cgi-url from .htaccess";
  } else {
    ($tests->{base_url} = $cgi_url) =~ s|/cgi-bin/\w+\.f?cgi$|/|;
  }

  $tests->SUPER::test_plan;
}

sub base_url {
  my MY $tests = shift;
  "http://localhost$tests->{base_url}";
}

sub ntests_per_item {
  (my MY $tests, my Item $item) = @_;
  lexpand($item->{cf_HEADER})/2
    + (($item->{cf_BODY} || $item->{cf_ERROR}) ? 1 : 0);
}

sub find_yatt_handler {
  my $pack = shift;
  local $_;
  foreach my $fn (@_) {
    open my $fh, '<', $fn or do { warn "$fn: $!"; next };
    while (<$fh>) {
      next unless m/^Action\s+x-yatt-handler\s+(\S+)/;
      return $1;
    }
  }
}
