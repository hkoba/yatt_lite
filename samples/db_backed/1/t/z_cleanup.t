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
use utf8;
use Test::More;

my $dbfn = "$app_root/data/.htdata.db";

unless (-r $dbfn and -s $dbfn) {
  plan skip_all => "There is no test database to cleanup.";
}

plan tests => 1;

ok(do_sqlite($dbfn, <<END), "deleting user 'hkoba'");
delete from user where login = 'hkoba'
END

sub do_sqlite {
  my ($fn, $sql) = @_;
  require DBI;
  my $dbh = DBI->connect("dbi:SQLite:dbname=$fn", undef, undef
			 , {PrintError => 0, RaiseError => 1, AutoCommit => 0});
  my $rc = $dbh->do($sql);
  $dbh->commit;
  $rc;
}
