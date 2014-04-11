package YATT::Lite::Embed; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw/all/;
use Carp;

#========================================
use YATT::Lite::Types
  ([Opts => fields => [qw/lazy
			  data_fh
			  helper_hook
			  callpack
			  filename
			  line
			  _yatt
			 /]]
 );

use YATT::Lite::Util qw/globref/;

sub import {
  my ($mypack, @rest) = @_;

  my Opts $opts = {};
  while (@rest) {
    if (not ref $rest[0]) {
      my ($k, $v) = splice @rest, 0, 2;
      $opts->{$k} = $v;
    } elsif (ref $rest[0] eq 'CODE') {
      $opts->{helper_hook} = shift @rest;
    } elsif (ref $rest[0] eq 'GLOB') {
      $opts->{data_fh} = shift @rest;
    } else {
      croak "Invalid argument! $rest[0]";
    }
  }

  ($opts->{callpack}, $opts->{filename}, $opts->{line}) = caller;
  $opts->{data_fh} //= globref($opts->{callpack}, 'DATA');

  # Make sure $YATT is declared.
  *{globref($opts->{callpack}, 'YATT')} = \ ($opts->{_yatt} = undef);

  if (not $mypack->known_blacklist($opts->{callpack})) {
    $mypack->install_CHECK_into($opts->{callpack}, $opts);
  } elsif (not eof $opts->{data_fh}) {
    $mypack->install_yatt_into($opts->{callpack}, $opts);
  } else {
    croak "Can't run CHECK on __DATA__ in do \"$opts->{filename}\".\n"
      ."(Hint: Directly running $opts->{filename} may solve this)";
  }
}

sub install_CHECK_into {
  (my $mypack, my $callpack, my Opts $opts) = @_;

  *{globref($callpack, 'YATT_EMBED_OPTS')} = \ $opts;

  my $script = <<END;
package $callpack; use strict; use warnings;
CHECK { $mypack->install_yatt_into(q!$callpack!, \$YATT_EMBED_OPTS) }
END

  {
    local $@;
    eval $script;
    die $@ if $@;
  }
}

sub known_blacklist {
  my ($mypack, $callpack) = @_;
  # Mojo uses do $fn, which causes this error:
  # Couldn't load application from file "hello.pl":
  #  Too late to run CHECK block at (eval 254) line 2.
  return 1 if $callpack =~ m{^Mojo::Server::SandBox};
}

#========================================

use YATT::Lite ();

sub YATT () {'YATT::Lite'}

sub install_yatt_into {
  (my $mypack, my $callpack, my Opts $opts) = @_;

  my $yatt = $mypack->YATT->new
    (vfs => [data => read_n_close($opts->{data_fh})]);

  $opts->{_yatt} = $yatt;

  if (my $sub = $opts->{helper_hook}) {
    $sub->($yatt);
  }

  unless ($opts->{lazy}) {
    $yatt->compile;
  }
}

sub read_n_close {
  my ($fh) = @_;
  local $/;
  my $data = <$fh>;
  close $fh;
  $data
}

1;
