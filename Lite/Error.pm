package YATT::Lite::Error; sub Error () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use parent qw(YATT::Lite::Object);

use YATT::Lite::MFields qw/cf_file cf_line cf_tmpl_file cf_tmpl_line
	      cf_backtrace
	      cf_reason cf_format cf_args/;
use overload qw("" message);
use YATT::Lite::Util qw(lexpand untaint_any);
use Carp;
require Scalar::Util;

sub message {
  my Error $error = shift;
  $error->reason . $error->place;
}

sub reason {
  my Error $error = shift;
  if ($error->{cf_reason}) {
    $error->{cf_reason};
  } elsif ($error->{cf_format}) {
    if (Scalar::Util::tainted($error->{cf_format})) {
      croak "Format is tainted in error reason("
	.join(" ", map {
	  if (defined $_) {
	    untaint_any($_)
	  } else {
	    '(undef)'
	  }
	} $error->{cf_format}, lexpand($error->{cf_args})).")";
    }
    sprintf $error->{cf_format}, map {
      defined $_ ? $_ : '(undef)'
    } lexpand($error->{cf_args});
  } else {
    "Unknown reason!"
  }
}

sub place {
  (my Error $err) = @_;
  my $place = '';
  $place .= " at file $err->{cf_tmpl_file}" if $err->{cf_tmpl_file};
  $place .= " line $err->{cf_tmpl_line}" if $err->{cf_tmpl_line};
  if ($err->{cf_file}) {
    $place .= ",\n reported from YATT Engine: $err->{cf_file} line $err->{cf_line}";
  }
  $place .= "\n" if $place ne ""; # To make 'warn/die' happy.
  $place;
}

1;
