use strict;
use warnings;
use Module::Build;

use FindBin;
use lib "$FindBin::Bin/runyatt.lib";

sub rscan_and_subst {
  my ($rscanSpec, $substSpec) = @_;
  my ($from, $to) = @$substSpec;
  my %hash = (
	      map {my ($std) = $_; $std =~ s{$from}{$to}; $_ => $std}
	      @{Module::Build->rscan_dir(@$rscanSpec)}
	     );
  \%hash;
}

my $builder = Module::Build->new
(module_name           => 'YATT::Lite'
 , license             => 'perl'
 , dist_version_from   => 'runyatt.lib/YATT/Lite.pm'
 , requires =>
 {'perl'       => '5.10.1' # for named capture and //
  , 'version'    => 0
  , 'List::Util' => 0
  , 'Test::More' => 0
  , 'Test::Differences' => 0
  , 'Plack' => 0.9982
 }

 , pm_files => rscan_and_subst
 (['runyatt.lib', qr{\.pm}]
  , [q{^runyatt.lib/}, q{lib/}])

 , test_files => Module::Build->rscan_dir('runyatt.lib/t', qr{\.t$})

 , script_files => rscan_and_subst
 (['runyatt.lib/YATT/scripts/', qr{\byatt\.\w+$}]
  , ["runyatt.lib/YATT/scripts/", q{bin/}])

 , add_to_cleanup      => [ qw(YATT-*
			       *.tmp
			       runyatt.lib/t/cover_db
			     ) ]
);

$builder->create_build_script();
