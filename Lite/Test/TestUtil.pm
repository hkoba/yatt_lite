package YATT::Lite::Test::TestUtil;
use strict;
use warnings FATAL => qw(all);

use Exporter qw(import);

our @EXPORT_OK = qw(eq_or_diff);
our @EXPORT = @EXPORT_OK;

require Test::More;

if (eval {require Test::Differences}) {
  *eq_or_diff = *Test::Differences::eq_or_diff;
} else {
  *eq_or_diff = *Test::More::is;
}

1;
