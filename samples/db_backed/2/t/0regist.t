#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use utf8;

use Test::More;

sub untaint_any {$_[0] =~ m{(.*)} and $1}
use FindBin;
use File::Basename;
use File::Spec;
my ($bindir, $libdir);
use lib (untaint_any
	 (File::Spec->rel2abs
	  ($libdir = ($bindir = dirname(untaint_any($0)))
	   . "/../../../../runyatt.lib"))
	 , $FindBin::Bin);

use YATT::Lite::TestUtil;

sub MY () {__PACKAGE__}
use base qw(t_regist);

MY->do_test($bindir, REQUIRE => [qw(DBD::mysql)]);

sub cleanup_sql {
  my ($pack, $mech, $bindir, $sql) = @_;
  my $passfile = "$bindir/../.htdbpass";

  unless (-r $passfile) {
    $mech->skip_all(".htdbpass is not configured");
  }

  do_mysql($passfile, $sql);
}

sub do_mysql {
  my ($fn, $sql) = @_;
  open my $fh, '<', $fn or die "Can't open '$fn': $!";
  my %opts;
  while (my $line = <$fh>) {
    chomp $line;
    next unless $line =~ /^(\w+): (.*)/;
    $opts{$1} = $2;
  }

  my @keys = qw(dbname dbuser dbpass);
  if (my @missing = grep {not defined $opts{$_}} @keys) {
    die "dbconfig (@missing) is missing\n";
  }
  my ($dbname, $dbuser, $dbpass) = @opts{@keys};
  require DBI;
  my $dbh = DBI->connect("dbi:mysql:database=$dbname", $dbuser, $dbpass
			 , {PrintError => 0, RaiseError => 1, AutoCommit => 0});
  $dbh->do($sql);
  $dbh->commit;
}
