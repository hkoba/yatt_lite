#!/usr/bin/env perl
package YATT::Lite::LRXML::AltTree;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base
  , [fields =>
     [string => doc => "source template string"],
     [with_source => default => 1, doc => "include source for intermediate nodes"],
     [with_text => doc => "include all text node"],
     [with_range => default => 1, doc => "include range for LSP"],
   ];

use YATT::Lite::LanguageServer::Protocol qw/Position Range/;

use MOP4Import::Types
  AltNode => [[fields => qw/
                             kind path source
                             symbol_range tree_range
                             subtree
                             value
                           /]];

use YATT::Lite::Constants
  qw/NODE_TYPE
     NODE_BEGIN NODE_END NODE_LNO
     NODE_SYM_END
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
  (my MY $self, my ($tree, $with_text)) = @_;
  map {
    if (not ref $_) {
      ($with_text || $self->{with_text}) ? $_ : ();
    } elsif (not ref $_->[NODE_TYPE]) {
      my AltNode $altnode = +{};
      $altnode->{kind} = $TYPES[$_->[NODE_TYPE]];
      $altnode->{path} = $self->convert_path_of($_);

      if (defined $_->[NODE_BEGIN] and defined $_->[NODE_END]
          and $_->[NODE_BEGIN] < length($self->{string})
          and $_->[NODE_END] < length($self->{string})) {
        my $source = substr($self->{string}, $_->[NODE_BEGIN]
                            , $_->[NODE_END] - $_->[NODE_BEGIN]);
        if ($self->{with_source}) {
          $altnode->{source} = $source;
        }
        if ($self->{with_range}) {
          $altnode->{tree_range} = $self->make_range(
            $_->[NODE_BEGIN],
            $_->[NODE_END],
            $_->[NODE_LNO],
            ($source =~ tr|\n||)
          );
          if ($_->[NODE_SYM_END]) {
            $altnode->{symbol_range} = $self->make_range(
              $_->[NODE_BEGIN],
              $_->[NODE_SYM_END] - 1,
              $_->[NODE_LNO],
            );
          }
        }
      }

      if ($_->[NODE_TYPE] == TYPE_ELEMENT || $_->[NODE_TYPE] == TYPE_ATT_NESTED) {
        my @origSubTree;
        if (my $attlist = $self->node_unwrap_attlist($_->[NODE_ATTLIST])) {
          push @origSubTree, $attlist;
        }
        if (my $subtree = $_->[NODE_AELEM_HEAD]) {
          push @origSubTree, $subtree;
        }
        if (defined $_->[NODE_BODY] and ref $_->[NODE_BODY] eq 'ARRAY') {
          push @origSubTree, $self->node_body_slot($_);
        }
        if (my $subtree = $_->[NODE_AELEM_FOOT]) {
          push @origSubTree, $subtree;
        }
        $altnode->{subtree} = [map {
          $self->convert_tree($_, $with_text);
        } @origSubTree];
      } else {
        if ($_->[NODE_TYPE] == TYPE_COMMENT) {
          $altnode->{value} = $_->[NODE_ATTLIST];
        } elsif ($_->[NODE_TYPE] == TYPE_ENTITY) {
          $altnode->{value} = [@{$_}[NODE_BODY .. $#$_]];
        } elsif (defined $_->[NODE_BODY] and ref $_->[NODE_BODY] eq 'ARRAY') {
          $altnode->{subtree} = [$self->convert_tree(
            $self->node_body_slot($_), $with_text
          )];
        } else {
          $altnode->{value} = $_->[NODE_BODY];
        }
      }
      $altnode;
    } else {
      # XXX: Is this ok?
      print STDERR "# really?: ".YATT::Lite::Util::terse_dump($tree), "\n";
      ...;
      # $self->convert_tree($_);
    }
  } @$tree;
}

sub make_range {
  (my MY $self, my ($begin, $end, $lineno, $nlines)) = @_;
  my Range $range = +{};
  $range->{start} = do {
    my Position $p;
    $p->{character} = $self->column_of_source_pos($self->{string}, $begin)-1;
    $p->{line} = $lineno - 1;
    $p;
  };
  $range->{end} = do {
    my Position $p;
    $p->{character} = $self->column_of_source_pos($self->{string}, $end-1);
    $p->{line} = $lineno - 1 + ($nlines // 0);
    $p;
  };
  $range;
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
    [$self->convert_tree($path, 1)]; # with_text
  } else {
    $path;
  }
}

sub list_types {
  @TYPES;
}

MY->run(\@ARGV) unless caller;
1;
