package YATT::Lite::XHF::Dumper;
use strict;
use warnings FATAL => qw(all);

use Exporter qw(import);
our @EXPORT_OK = qw(dump_xhf);
our @EXPORT = @EXPORT_OK;

use 5.010;
use Carp;

use YATT::Lite::XHF qw($cc_name);

sub dump_xhf {
  shift;
  _dump_pairs(@_);
}

sub _dump_pairs {
  my @buffer;
  while (@_) {
    if (@_ == 1 or not defined $_[0] or ref $_[0]) {
      push @buffer, _dump_value(shift, '-');
    } elsif ($_[0] !~ m{^$cc_name*$}) {
      push @buffer, '-' . escape(shift), _dump_value(shift, '-');
    } else {
      push @buffer, shift() . _dump_value(shift, ':');
    }
  }
  join "\n", @buffer;
}

sub _dump_value {
    # value part.
  unless (defined $_[0]) {
    "= #null";
  } elsif (not ref $_[0]) {
    $_[1] . escape(shift);
  } elsif (ref $_[0] eq 'ARRAY') {
    dump_array(shift);
  } elsif (ref $_[0] eq 'HASH') {
    dump_hash(shift);
  } else {
    croak "Can't dump ref as XHF: $_[0]";
  }
}

sub escape {
  my ($str) = @_;
  my $sep = $str =~ /^\s+|\s+$/s ? "\n" : " ";
  $str =~ s/\n/\n /g;
  $sep . $str;
}

sub dump_array {
  my ($item) = @_;
  "[\n" . join("\n", map {_dump_value($_, '-')} @$item) . "\n]";
}

sub dump_hash {
  my ($item) = @_;
  "{\n" . _dump_pairs(map {$_, $item->{$_}} sort keys %$item) . "\n}";
}
