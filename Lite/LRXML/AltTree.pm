#!/usr/bin/env perl
package YATT::Lite::LRXML::AltTree;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base
  , [fields =>
     [string => doc => "source template string"],
     [all_source => doc => "include all source for intermediate nodes instead of leaf only"],
   ];

use YATT::Lite::LanguageServer::Protocol qw/Position Range/;

use MOP4Import::Types
  AltNode => [[fields => qw/
                             kind path source range
                             attlist
                             head subtree foot
                             value
                           /]];

use YATT::Lite::Constants
  qw/NODE_TYPE
     NODE_BEGIN NODE_END NODE_LNO
     NODE_PATH NODE_BODY NODE_VALUE
     NODE_ATTLIST NODE_AELEM_HEAD NODE_AELEM_FOOT
     TYPE_ELEMENT TYPE_LCMSG
     TYPE_ATT_NESTED
     TYPE_COMMENT
     TYPE_ENTITY

     node_unwrap_attlist
    /;
# XXX: Adding *TYPE_ / @TYPE_ to @YATT::Lite::Constants::EXPORT_OK didn't work
# Why?
*TYPES = *YATT::Lite::Constants::TYPE_;*TYPES = *YATT::Lite::Constants::TYPE_;
our @TYPES;

use YATT::Lite::XHF::Dumper qw/dump_xhf/;
sub cli_write_fh_as_xhf {
  (my MY $self, my ($outFH, @args)) = @_;
  foreach my $list (@args) {
    print $outFH $self->dump_xhf($list), "\n";
  }
}

sub convert_tree {
  (my MY $self, my ($tree)) = @_;
  [map {
    if (not ref $_) {
      $_;
    } elsif (not ref $_->[NODE_TYPE]) {
      my AltNode $altnode = +{};
      $altnode->{kind} = $TYPES[$_->[NODE_TYPE]];
      $altnode->{path} = $self->convert_path_of($_);

      if (defined $_->[NODE_BEGIN] and defined $_->[NODE_END]
          and $_->[NODE_BEGIN] < length($self->{string})
          and $_->[NODE_END] < length($self->{string})) {
        $altnode->{range} = my Range $range = +{};
        $altnode->{source} = my $source = substr($self->{string}, $_->[NODE_BEGIN]
                                                 , $_->[NODE_END] - $_->[NODE_BEGIN]);
        $range->{start} = do {
          my Position $p;
          $p->{character} = $self->column_of_source_pos($self->{string}, $_->[NODE_BEGIN])-1;
          $p->{line} = $_->[NODE_LNO] - 1;
          $p;
        };
        $range->{end} = do {
          my Position $p;
          $p->{character} = $self->column_of_source_pos($self->{string}, $_->[NODE_END]-1);
          $p->{line} = $_->[NODE_LNO] - 1 + ($source =~ tr|\n||);
          $p;
        };
      }
      do {
        if ($_->[NODE_TYPE] == TYPE_COMMENT) {
          $altnode->{value} = $_->[NODE_ATTLIST];
        } elsif ($_->[NODE_TYPE] == TYPE_ENTITY) {
          $altnode->{value} = $_->[NODE_BODY];
        } elsif (defined $_->[NODE_BODY] and ref $_->[NODE_BODY] eq 'ARRAY') {
          $altnode->{subtree} = $self->convert_tree(
            $self->node_body_slot($_)
          )
        } else {
          $altnode->{value} = $_->[NODE_BODY];
        }
      };
      if ($_->[NODE_TYPE] == TYPE_ELEMENT
          || $_->[NODE_TYPE] == TYPE_ATT_NESTED
        ) {
        if (my $attlist = $self->node_unwrap_attlist($_->[NODE_ATTLIST])) {
          $altnode->{attlist} = $self->convert_tree($attlist);
        }
        foreach my $item ([head => NODE_AELEM_HEAD], [foot => NODE_AELEM_FOOT]) {
          my ($key, $ix) = @$item;
          if ($_->[$ix]) {
            $altnode->{$key} = $self->convert_tree($_->[$ix]);
          }
        }
      }
      $altnode;
    } else {
      # XXX: Is this ok?
      print STDERR "# really?: ".YATT::Lite::Util::terse_dump($tree), "\n";
      ...;
      # $self->convert_tree($_);
    }
  } @$tree];
}

sub column_of_source_pos {
  my $pos = $_[2];
  if ((my $found = rindex($_[1], "\n", $pos)) >= 0) {
    $pos - $found;
  } else {
    $pos;
  }
}

sub node_body_slot {
  my ($self, $node) = @_;
  if ($node->[NODE_TYPE] == TYPE_ELEMENT) {
    return $node->[NODE_BODY] ? $node->[NODE_BODY][NODE_VALUE] : undef;
  } elsif ($node->[NODE_TYPE] == TYPE_LCMSG) {
    return $node->[NODE_BODY] ? $node->[NODE_BODY][0] : undef;
  } else {
    return $node->[NODE_VALUE];
  }
}

sub convert_path_of {
  my ($self, $node) = @_;
  my $path = $node->[NODE_PATH];
  if ($path and ref $path and @$path and ref $path->[0]) {
    $self->convert_tree($path)
  } else {
    $path;
  }
}

sub list_types {
  @TYPES;
}

MY->run(\@ARGV) unless caller;
1;
