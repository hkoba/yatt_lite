#!/usr/bin/perl -w
sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use 5.010;

sub untaint_any {$_[0] =~ m{(.*)} and $1}
use FindBin;
use File::Basename;
use File::Spec;
use lib "$FindBin::Bin/../lib";

use YATT::Lite::Breakpoint;
use YATT::Lite::XHFTest2;
use base qw(YATT::Lite::XHFTest2);
use fields qw(base_url);
use YATT::Lite::Util qw(lexpand);

my $appdir = "$FindBin::Bin/..";

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
