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

my $passfile = "$bindir/../.htdbpass";
unless (-r $passfile) {
  plan skip_all => ".htdbpass is not configured";
}

do_mysql($passfile, <<END);
delete from user where login = 'hkoba'
END

plan skip_all => "This is cleanup only test.";

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
