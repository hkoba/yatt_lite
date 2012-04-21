use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/misc/cpan";

use MyBuilder;

my $builder = MyBuilder->new
(module_name           => 'YATT::Lite'
 , license             => 'perl'
 , dist_version_from   => 'Lite.pm'

 , requires =>
 {'perl'       => '5.10.1' # for named capture and //
  , 'version'    => 0
  , 'List::Util' => 0
 }

 , build_requires =>
 {'Test::More' => 0
  , 'Test::Differences' => 0
  , 'File::ShareDir' => 0
 }

 # , test_files => Module::Build->rscan_dir('t', qr{\.t$})

 , add_to_cleanup      => [ qw(YATT-*
			       *.tmp
			       t/cover_db
			     ) ]
);

$builder->create_build_script();
