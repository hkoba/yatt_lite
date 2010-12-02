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
use YATT::Lite::Util qw(ostream);
use YATT::Lite::XHFTest2;
use base qw(YATT::Lite::XHFTest2);

my MY $tests = MY->load_tests([dir => "$bindir/.."
			       , libdir => untaint_any
			       (File::Spec->rel2abs($libdir))]
			      , @ARGV ? @ARGV : $bindir);
$tests->enter;

plan $tests->test_plan;

my $dispatcher = $tests->load_dispatcher;
$dispatcher->configure(at_done => sub { die \"DONE"; });

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

    my (@param) = $dispatcher->make_cgi
      ("./$item->{cf_FILE}", $item->{cf_PARAM});

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
