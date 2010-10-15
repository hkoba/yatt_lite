package YATT::Lite::Util::Enum;
use strict;
use warnings FATAL => qw(all);
use YATT::Lite::Util qw(globref);

sub import {
  my $pack = shift;
  my $callpack = caller;
  my ($export, $export_ok) = map {
    my $glob = globref($callpack, $_);
    unless (*{$glob}{ARRAY}) {
      *$glob = [];
    }
    *{$glob}{ARRAY};
  } qw(EXPORT EXPORT_OK);
  while (@_ and my ($prefix, $enumList) = splice @_, 0, 2) {
    my $offset = 0;
    foreach my $item (@$enumList) {
      foreach my $name (split /=/, $item) {
	my $shortName = $prefix . $name;
	my $fullName = $callpack . "::" . $shortName;
	# print STDERR "$fullName\n";
	my $glob = do {no strict 'refs'; \*$fullName};
	my $i = $offset;
	*$glob = sub () {$i};
	unless ($shortName =~ /^_/) {
	  push @$export_ok, $shortName;
	  push @$export, $shortName;
	}
      }
    } continue {
      $offset++;
    }
  }
}

1;
