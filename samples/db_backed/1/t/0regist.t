#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use utf8;
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

sub MY () {__PACKAGE__}
use base qw(t_regist);

MY->do_test($bindir, REQUIRE => [qw(DBD::SQLite)]);

sub cleanup_sql {
  my ($pack, $mech, $bindir, $sql) = @_;
  do_sqlite("$bindir/../data/.htdata.db", $sql);
}

sub do_sqlite {
  my ($fn, $sql) = @_;
  require DBI;
  my $dbh = DBI->connect("dbi:SQLite:dbname=$fn", undef, undef
			 , {PrintError => 0, RaiseError => 1, AutoCommit => 0});
  $dbh->do($sql);
  $dbh->commit;
}
