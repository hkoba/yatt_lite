#!/usr/bin/perl -w
sub MY () {__PACKAGE__}
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

use YATT::Lite::Breakpoint;
use YATT::Lite::XHFTest2;
use base qw(YATT::Lite::XHFTest2);
use fields qw(base_url mech);
use YATT::Lite::Util qw(lexpand);

my MY $tests = MY->load_tests([dir => "$bindir/.."
			       , libdir => untaint_any
			       (File::Spec->rel2abs($libdir))]
			      , @ARGV ? @ARGV : $bindir);
$tests->enter;

plan $tests->test_plan;

foreach my File $sect (@{$tests->{files}}) {
  my $dir = $tests->{cf_dir};
  my $sect_name = $tests->file_title($sect);
  foreach my Item $item (@{$sect->{items}}) {

    if (my $action = $item->{cf_ACTION}) {
      my ($method, @args) = @$action;
      my $sub = $tests->can("action_$method")
	or die "No such action: $method";
      $sub->($tests, @args);
      next;
    }

    my $url = $tests->item_url($item);
    my $res;
    my $method = $item->{cf_METHOD} // 'GET';
    given ($method) {
      when ('GET') {
	$res = $tests->{mech}->get($url);
      }
      when ('POST') {
	$res = $tests->{mech}->post($url, $item->{cf_PARAM});
      }
      default {
	die "Unknown test method: $_\n";
      }
    }

    if ($item->{cf_HEADER} and my @header = @{$item->{cf_HEADER}}) {
      while (my ($key, $pat) = splice @header, 0, 2) {
	like $res->header($key), qr{$pat}s
	  , "[$sect_name] HEADER $key of $method $item->{cf_FILE}";
      }
    }

    if ($item->{cf_BODY}) {
      if (ref $item->{cf_BODY}) {
	like nocr($tests->{mech}->content), $tests->mkseqpat($item->{cf_BODY})
	  , "[$sect_name] BODY of $method $item->{cf_FILE}";
      } else {
	eq_or_diff trimlast(nocr($tests->{mech}->content)), $item->{cf_BODY}
	  , "[$sect_name] BODY of $method $item->{cf_FILE}";
      }
    } elsif ($item->{cf_ERROR}) {
      like $tests->{mech}->content, qr{$item->{cf_ERROR}}
	, "[$sect_name] ERROR of $method $item->{cf_FILE}";
    }
  }
}

sub test_plan {
  my MY $tests = shift;
  unless (eval {require WWW::Mechanize}) {
    return skip_all => 'WWW::Mechanize is not installed';
  }

  $tests->{mech} = new WWW::Mechanize(max_redirect => 0);

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

sub item_url {
  (my MY $tests, my Item $item) = @_;
  join '?', "http://localhost$tests->{base_url}$item->{cf_FILE}"
    , ($item->{cf_PARAM} ? join('&', map {
      "$_=".$item->{cf_PARAM}{$_}
    } keys %{$item->{cf_PARAM}}) : ());
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
