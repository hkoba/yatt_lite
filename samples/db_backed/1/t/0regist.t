#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use utf8;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use FindBin;
use File::Basename;
use File::Spec;
use lib $FindBin::Bin, "$FindBin::Bin/../lib";

sub MY () {__PACKAGE__}
use base qw(t_regist);

MY->do_test("$FindBin::Bin/..", REQUIRE => [qw(DBD::SQLite)]);

sub cleanup_sql {
  my ($pack, $app, $app_root, $sql) = @_;
  do_sqlite("$app_root/data/.htdata.db", $sql);
}

sub do_sqlite {
  my ($fn, $sql) = @_;
  require DBI;
  my $dbh = DBI->connect("dbi:SQLite:dbname=$fn", undef, undef
			 , {PrintError => 0, RaiseError => 1, AutoCommit => 0});
  $dbh->do($sql);
  $dbh->commit;
}
