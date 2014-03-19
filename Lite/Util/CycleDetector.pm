# -*- coding: utf-8 -*-

# This package is used to implement modified version of following algorithm:
#
#   http://en.wikipedia.org/wiki/Topological_sorting#CITEREFCormenLeisersonRivestStein2001
#
#   Cormen, Thomas H.; Leiserson, Charles E.; Rivest, Ronald L.;
#   Stein, Clifford (2001),
#   "Section 22.4: Topological sort", Introduction to Algorithms (2nd ed.),
#   MIT Press and McGraw-Hill, pp. 549–552, ISBN 0-262-03293-7.
#

package YATT::Lite::Util::CycleDetector;
use strict;
use warnings FATAL => qw/all/;
use Carp;

use Exporter qw/import/;
our @EXPORT_OK = qw/Visits/;

sub Visits () {__PACKAGE__}
use YATT::Lite::MFields qw/nodes time/;

use YATT::Lite::Types
  ([Node => fields => [qw/path discovered finished color parent/]]);
use YATT::Lite::Util::Enum
  (NTYPE_ => [qw/WHITE GRAY BLACK/]
   , EDGE_ => [qw/TREE BACK FORW CROSS/]);

sub start {
  my ($pack, $path) = @_;
  my Visits $vis = bless {}, $pack;
  $vis->{time} = 0;
  $vis->ensure_make_node($path);
  $vis->visit_node($path);
  $vis;
}

sub has_node {
  (my Visits $vis, my $path) = @_;
  $vis->{nodes}{$path};
}

sub ensure_make_node {
  (my Visits $vis, my @path) = @_;
  foreach my $path (@path) {
    next if $vis->{nodes}{$path};
    $vis->make_node($path);
  }
  @path;
}

sub make_node {
  (my Visits $vis, my ($path)) = @_;
  $vis->{nodes}{$path} = my Node $node = {};
  $node->{path} = $path;
  $node->{color} = NTYPE_WHITE;
  $node;
}

sub visit_node {
  (my Visits $vis, my ($path, $parent)) = @_;
  my Node $node = $vis->{nodes}{$path}
    or croak "No such path in visits! $path";
  $node->{color} = NTYPE_GRAY;
  $node->{discovered} = ++$vis->{time};
  $node->{parent} = $vis->{nodes}{$parent} if $parent;
  $node;
}

sub finish_node {
  (my Visits $vis, my $path) = @_;
  my Node $node = $vis->{nodes}{$path}
    or croak "No such path in visits! $path";
  $node->{color} = NTYPE_BLACK;
  $node->{finished} = ++$vis->{time};
  $node;
}

sub check_cycle {
  (my Visits $vis, my ($to, $from)) = @_;
  my Node $dest = $vis->{nodes}{$to}
    or croak "No such path in visits! $to";
  if ($dest->{color} == NTYPE_WHITE) {
    # tree edge
    $vis->visit_node($to);
  } elsif ($dest->{color} == NTYPE_GRAY) {
    # back edge!
    return [$to, $vis->list_cycle($dest)]
  } else {
    # forward or cross
  }
  return;
}

sub list_cycle {
  (my Visits $vis, my Node $node) = @_;
  my @path;
  while ($node and $node->{parent}) {
    $node = $node->{parent};
    push @path, $node->{path};
  }
  @path;
}

1;
