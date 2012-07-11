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
    $app_root = dirname(dirname(File::Spec->rel2abs(__FILE__)));
  } else {
    # older uwsgi do not set __FILE__ correctly, so use cwd instead.
    $app_root = Cwd::cwd();
  }
  my $dn;
  if (-d (($dn = "$app_root/lib") . "/YATT")) {
    push @libdir, $dn
  } elsif (($dn) = $app_root =~ m{^(.*?/)YATT/}) {
    push @libdir, $dn;
  }
}
use lib $FindBin::Bin, @libdir;
#----------------------------------------


use utf8;
use base qw(t_regist);

MY->do_test("$FindBin::Bin/..", REQUIRE => [qw(DBD::SQLite)]);

sub cleanup_sql {
  my ($pack, $app, $dbh, $app_root, $sql) = @_;
  do_sqlite($dbh, "$app_root/data/.htdata.db", $sql);
}

sub do_sqlite {
  my ($dbh, $fn, $sql) = @_;
  require DBI;
  $dbh ||= DBI->connect("dbi:SQLite:dbname=$fn", undef, undef
			, {PrintError => 0, RaiseError => 1, AutoCommit => 0});
  $dbh->do($sql);
  $dbh->commit unless $dbh->{AutoCommit};
}
