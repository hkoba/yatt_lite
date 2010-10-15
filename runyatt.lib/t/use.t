#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);

use FindBin;
use lib "$FindBin::Bin/..";

use Test::More qw(no_plan);

ok(chdir $FindBin::Bin, 'chdir to test dir');

use File::Find;

my %prereq;

my %ignore; map ++$ignore{$_}, ();

my (%modules, @modules);
find sub {
  my $name = $File::Find::name;
  return unless $name =~ m{\.pm$};
  $name =~ s{^\../}{};
  $name =~ s{/}{::}g;
  $name =~ s{\.pm$}{}g;
  return if $ignore{$name};
  print "$File::Find::name => $name\n" if $ENV{VERBOSE};
  $modules{$name} = $File::Find::name;
  push @modules, $name;
}, '../YATT';

sub fgrep {
  my ($pattern, $file) = @_;
  open my $fh, '<', $file or die "Can't open $file: $!";
  my @result;
  while (defined(my $line = <$fh>)) {
    next unless $line =~ $pattern;
    push @result, $line;
  }
  @result;
}

foreach my $mod (@modules) {
 SKIP: {
    if (my $req = $prereq{$mod}) {
      foreach my $m (@$req) {
	unless (eval "require $m") {
	  skip "testing $mod requires $m", 3;
	}
      }
    }
    require_ok($mod);
    ok scalar fgrep(qr/^use strict;$/, $modules{$mod})
      , "is strict: $mod";
    ok scalar fgrep(qr/^use warnings FATAL/, $modules{$mod})
      , "is warnings $mod";
  }
}
