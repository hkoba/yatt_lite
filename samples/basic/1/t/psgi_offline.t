#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
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

sub MY () {__PACKAGE__}

sub untaint_any {$_[0] =~ m{(.*)} and $1}
use File::Basename;
use File::Spec;
my ($bindir, $libdir);
BEGIN {
  # To allow keeping relative dir.
  $bindir = untaint_any(dirname($0));
  if (-x "$bindir/../cgi-bin/runyatt.cgi"
      and -d (my $dn = "$bindir/../cgi-bin/runyatt.lib")) {
    $libdir = $dn;
  } else {
    require Test::More;
    Test::More::plan(skip_all => 'Not yet setup');
  }
}
use lib untaint_any(File::Spec->rel2abs($libdir));

use YATT::Lite::Breakpoint;
# use YATT::Lite::Util qw(ostream);
use YATT::Lite::XHFTest2;
use base qw(YATT::Lite::XHFTest2);

my MY $tests = MY->load_tests([dir => "$bindir/.."
			       , libdir => untaint_any
			       (File::Spec->rel2abs($libdir))]
			      , @ARGV ? @ARGV : $bindir);
$tests->enter;

plan $tests->test_plan(1);

use Cwd;
$ENV{YATT_DOCUMENT_ROOT} = cwd;
ok(my $app = Plack::Util::load_psgi("runyatt.psgi"), "load_psgi");

test_psgi $app, sub {
  my ($cb) = shift;
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

      $item->{cf_METHOD} //= 'GET';
      my $T = defined $item->{cf_TITLE} ? "[$item->{cf_TITLE}]" : '';

      my $res = $cb->(my $req = $tests->http_request($item));

      if ($item->{cf_ERROR}) {
	(my $str = $res->content) =~ s/^Internal Server error\n//;
	like $str, qr{$item->{cf_ERROR}}
	  , "[$sect_name] $T ERROR $item->{cf_METHOD} $item->{cf_FILE}";
	next;
      } elsif ($res->code != 200) {
	Test::More::fail $item->{cf_FILE};
	Test::More::diag $res->content;
	next;
      }

      if ($item->{cf_METHOD} eq 'POST' and $item->{cf_HEADER}) {
	like trimlast(nocr($res->content)), $tests->mkpat($item->{cf_HEADER})
	  , "[$sect_name] $T POST $item->{cf_FILE}";
      } elsif (ref $item->{cf_BODY}) {
	like nocr($res->content), $tests->mkseqpat($item->{cf_BODY})
	  , "[$sect_name] $T $item->{cf_METHOD} $item->{cf_FILE}";
      } else {
	eq_or_diff trimlast(nocr($res->content)), $item->{cf_BODY}
	  , "[$sect_name] $T $item->{cf_METHOD} $item->{cf_FILE}";
      }
    }
  }
};

sub base_url {
  shift; "http://localhost/";
}
