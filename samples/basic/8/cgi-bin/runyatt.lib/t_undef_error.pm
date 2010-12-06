package
 t_undef_error;
use strict;
# no warnings;

use Exporter qw(import);
our @EXPORT = qw(t_undef_error);

sub t_undef_error {
  undef() . @_;
}

1;
