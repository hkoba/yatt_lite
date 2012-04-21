#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);

sub untaint_any {$_[0] =~ m{(.*)} and $1}
use FindBin;
BEGIN {$FindBin::Bin = untaint_any($FindBin::Bin)}
use lib "$FindBin::Bin/lib";

use Test::More;

chdir $FindBin::Bin
  or die "chdir to test dir failed: $!";

use File::Find;

my %prereq
  = ('YATT::Lite::DBSchema::DBIC' => ['DBIx::Class::Schema']);

my %ignore; map ++$ignore{$_}, ();


my @modules = ('YATT::Lite');
my (%modules) = ('YATT::Lite' => "lib/YATT/Lite.pm");
find {
  no_chdir => 1,
  wanted => sub {
  my $name = $File::Find::name;
  return unless $name =~ m{\.pm$};
  $name =~ s{^lib/}{};
  $name =~ s{/}{::}g;
  $name =~ s{\.pm$}{}g;
  return if $ignore{$name};
  print "$File::Find::name => $name\n" if $ENV{VERBOSE};
  $modules{$name} = $File::Find::name;
  push @modules, untaint_any($name);
}}, untaint_any('lib/YATT/Lite/');

plan tests => 3 * @modules;

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
