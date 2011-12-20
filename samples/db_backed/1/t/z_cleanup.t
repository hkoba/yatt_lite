#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use utf8;

use Test::More;

sub untaint_any {$_[0] =~ m{(.*)} and $1}
use File::Basename;
use File::Spec;
my ($bindir, $libdir);
use lib untaint_any
  (File::Spec->rel2abs
   ($libdir = ($bindir = dirname(untaint_any($0)))
    . "/../../../../runyatt.lib"));

unless (-d "$bindir/../cgi-bin"
	and grep {-x "$bindir/../cgi-bin/runyatt.$_"} qw(cgi fcgi)) {
  plan skip_all => "Can't find cgi-bin/runyatt.cgi";
}

my $dbfn = "$bindir/../data/.htdata.db";

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
