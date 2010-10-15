package YATT::Lite::Util::CmdLine;
use strict;
use warnings FATAL => qw(all);

BEGIN {require Exporter; *import = \&Exporter::import}

our @EXPORT = qw(parse_opts parse_params);
our @EXPORT_OK = (@EXPORT, qw(run));

# posix style option.
sub parse_opts {
  my ($pack, $list, $result, $alias) = @_;
  my $wantarray = wantarray;
  unless (defined $result) {
    $result = $wantarray ? [] : {};
  }
  while (@$list and my ($n, $v) = $list->[0]
	 =~ m{^(?:--? ([\w:\-\.]+) (?: =(.*))? | -- )$}xs) {
    shift @$list;
    last unless defined $n;
    $n = $alias->{$n} if $alias and $alias->{$n};
    $v = 1 unless defined $v;
    if (ref $result eq 'HASH') {
      $result->{$n} = $v;
    } else {
      push @$result, $n, $v;
    }
  }
  $wantarray && ref $result ne 'HASH' ? @$result : $result;
}

# 'Make' style parameter.
sub parse_params {
  my ($pack, $list, $hash) = @_;
  my $explicit;
  unless (defined $hash) {
    $hash = {}
  } else {
    $explicit++;
  }
  for (; @$list and $list->[0] =~ /^([^=]+)=(.*)/; shift @$list) {
    $hash->{$1} = $2;
  }
  if (not $explicit and wantarray) {
    # return empty list if hash is empty
    %$hash ? $hash : ();
  } else {
    $hash
  }
}

sub run {
  my ($pack, $list, $alias) = @_;

  my $app = $pack->new(parse_opts($pack, $list, $alias));

  my $cmd = shift @$list || 'help';

  if (my $sub = $app->can("cmd_$cmd")) {
    $sub->($app, @$list);
  } elsif ($sub = $app->can($cmd)) {
    my @res = $sub->($app, @$list);
  } else {
    die "$0: Unknown subcommand '$cmd'\n"
  }
}

1;
