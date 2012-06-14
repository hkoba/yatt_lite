package
  YATT::t::t_preload;
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

#
# Without these preloading, some tests failed under Devel::Cover
# (Caused by warnings like "Can't open ... for MD5 digest")
#
use YATT::Lite::LRXML ();
use YATT::Lite::LRXML::ParseBody ();
use YATT::Lite::LRXML::ParseEntpath ();
use YATT::Lite::Core ();
use YATT::Lite::CGen::Perl ();


1;
