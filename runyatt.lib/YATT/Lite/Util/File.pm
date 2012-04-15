package YATT::Lite::Util::File;
use strict;
use warnings FATAL => qw(all);
use YATT::Lite::Util ();
use File::Basename qw(dirname);

sub mkfile {
  my ($pack, $fn, $content) = @_;
  ($fn, my @iolayer) = ref $fn ? @$fn : ($fn);
  unless (-d (my $dir = dirname($fn))) {
    mkdir $dir or die "Can't mkdir $dir: $!";
  }
  open my $fh, join('', '>', @iolayer), $fn or die "$fn: $!";
  print $fh $content;
}

# Auto Export.
my $symtab = YATT::Lite::Util::symtab(__PACKAGE__);
our @EXPORT_OK = grep {
  *{$symtab->{$_}}{CODE}
} keys %$symtab;

use Exporter qw(import);

1;
