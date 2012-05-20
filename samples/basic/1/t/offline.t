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
use YATT::Lite::Util qw(ostream);
use YATT::Lite::Test::XHFTest2; # To import Item class.
use base qw(YATT::Lite::Test::XHFTest2); # XXX: Redundant, but required.

my MY $tests = MY->load_tests([dir => "$FindBin::Bin/../html"]
			      , @ARGV ? @ARGV : $FindBin::Bin);
$tests->enter;

plan $tests->test_plan;

my $dispatcher = $tests->load_dispatcher;
# $dispatcher->configure(at_done => sub { die \"DONE"; });

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

    my %env = (DOCUMENT_ROOT => $dir
	       , PATH_INFO => "/$item->{cf_FILE}"
	       , PATH_TRANSLATED => "$dir/$item->{cf_FILE}"
	      );
    my (@param) = $dispatcher->make_cgi
      (\%env, ["./$item->{cf_FILE}", $item->{cf_PARAM}]);

    $item->{cf_METHOD} //= 'GET';
    my $T = defined $item->{cf_TITLE} ? "[$item->{cf_TITLE}]" : '';

    my $con = ostream(my $buffer);
    eval {$dispatcher->run_dirhandler($con, @param)->commit};

    if ($item->{cf_ERROR}) {
      like $@, qr{$item->{cf_ERROR}}
	, "[$sect_name] $T ERROR $item->{cf_METHOD} $item->{cf_FILE}";
      next;
    } elsif (ref $@ eq 'SCALAR' and ${$@} eq 'DONE') {
      # Request is completed.
    } elsif ($@) {
      Test::More::fail $item->{cf_FILE};
      Test::More::diag $@;
      next;
    }

    if ($item->{cf_METHOD} eq 'POST' and $item->{cf_HEADER}) {
      like trimlast(nocr($buffer)), $tests->mkpat($item->{cf_HEADER})
	, "[$sect_name] $T POST $item->{cf_FILE}";
    } elsif (ref $item->{cf_BODY}) {
      like nocr($buffer), $tests->mkseqpat($item->{cf_BODY})
	, "[$sect_name] $T $item->{cf_METHOD} $item->{cf_FILE}";
    } else {
      eq_or_diff trimlast(nocr($buffer)), $item->{cf_BODY}
	, "[$sect_name] $T $item->{cf_METHOD} $item->{cf_FILE}";
    }
  }
}

sub test_plan {
  my MY $self = shift;
  # XXX: This is overkill!
  foreach my File $file (@{$self->{files}}) {
    if ($file->{cf_USE_COOKIE}) {
      return skip_all => "Cookie is not yet supported in offline.t";
    }
  }
  $self->SUPER::test_plan;
}
