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
my $libdir;
BEGIN {
  unless (grep {$_ eq 'YATT'} MY->splitdir($FindBin::Bin)) {
    die "Can't find YATT in runtime path: $FindBin::Bin\n";
  }
  $libdir = dirname(dirname(untaint_any($FindBin::Bin)));
}
use lib $libdir;
#----------------------------------------

use Test::More;

chdir $FindBin::Bin
  or die "chdir to test dir failed: $!";

my ($lib_yatt) = grep(-e "$_/YATT/Lite"
		      , 'lib', @INC);

unless (defined $lib_yatt) {
  BAIL_OUT("lib/YATT is missing??");
}

use File::Find;

my %prereq
  = ('YATT::Lite::WebMVC0::DBSchema::DBIC' => [qw/DBIx::Class::Schema/]
     , 'YATT::Lite::Test::TestFCGI' => [qw/HTTP::Response/]
    );

my %ignore; map ++$ignore{$_}, ();


my @modules = ('YATT::Lite');
my (%modules) = ('YATT::Lite' => "$lib_yatt/YATT/Lite.pm");
find {
  no_chdir => 1,
  wanted => sub {
  my $name = $File::Find::name;
  return unless $name =~ m{\.pm$};
  $name =~ s{^\Q$lib_yatt\E/}{};
  $name =~ s{/}{::}g;
  $name =~ s{\.pm$}{}g;
  return if $ignore{$name};
  print "$File::Find::name => $name\n" if $ENV{VERBOSE};
  $modules{$name} = $File::Find::name;
  push @modules, untaint_any($name);
}}, untaint_any("$lib_yatt/YATT/Lite");

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
