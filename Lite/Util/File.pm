package YATT::Lite::Util::File;
use strict;
use warnings FATAL => qw(all);
use YATT::Lite::Util ();
use File::Basename qw(dirname);
use File::Path qw(make_path);

sub mkfile {
  my ($pack) = shift;
  while (my ($fn, $content) = splice @_, 0, 2) {
    ($fn, my @iolayer) = ref $fn ? @$fn : ($fn);
    unless (-d (my $dir = dirname($fn))) {
      make_path($dir) or die "Can't mkdir $dir: $!";
    }
    open my $fh, join('', '>', @iolayer), $fn or die "$fn: $!";
    print $fh $content;
  }
}

# Auto Export.
my $symtab = YATT::Lite::Util::symtab(__PACKAGE__);
our @EXPORT_OK = grep {
  *{$symtab->{$_}}{CODE}
} keys %$symtab;

use Exporter qw(import);

1;
