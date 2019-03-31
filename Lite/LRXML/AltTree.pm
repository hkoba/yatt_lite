#!/usr/bin/env perl
package YATT::Lite::LRXML::AltTree;
use strict;
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base
  , [fields =>
     [string => doc => "source template string"],
     [all_source => doc => "include all source for intermediate nodes instead of leaf only"],
   ];

use YATT::Lite::Constants
  qw/NODE_TYPE NODE_BEGIN NODE_END NODE_PATH NODE_BODY NODE_VALUE
     TYPE_ELEMENT TYPE_LCMSG/;
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
      my $source;
      if ($_->[NODE_BEGIN] and $_->[NODE_END]
          and $_->[NODE_BEGIN] < length($self->{string})
          and $_->[NODE_END] < length($self->{string})) {
        $source = substr($self->{string}, $_->[NODE_BEGIN], $_->[NODE_END]);
      }
      my @rest = do {
        if (defined $_->[NODE_BODY] and ref $_->[NODE_BODY] eq 'ARRAY') {
          (subtree => $self->convert_tree(
            $self->node_body_slot($_))
         )
        } else {
          (value => $_->[NODE_BODY]);
        }
      };
      # if ($_->[NODE_TYPE] == TYPE_ELEMENT) {
      # ATTLIST AELEM_HEAD AELEM_FOOT
      # }
      unless (@rest % 2 == 0) {
        die "XXX";
      }
      +{kind => $TYPES[$_->[NODE_TYPE]], path => $_->[NODE_PATH]
        , source => $source
        , @rest
      };
    } else {
      ...
    }
  } @$tree];
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



sub list_types {
  @TYPES;
}

MY->run(\@ARGV) unless caller;
1;
