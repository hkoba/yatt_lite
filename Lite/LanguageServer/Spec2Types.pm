#!/usr/bin/env perl
package YATT::Lite::LanguageServer::Spec2Types;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base
  , [fields =>
     [with_field_docs => doc => "generate field documents too"],
   ]
  , [output_format => indented => sub {
    my ($self, $outFH, @args) = @_;
    require Data::Dumper;
    foreach my $list (@args) {
      foreach my $item (@$list) {
        print $outFH Data::Dumper->new([$item])->Indent(1)->Terse(1)
          ->Dump =~ s/\n\z/,\n/r;
      }
    }
  }];

use YATT::Lite::LanguageServer::SpecParser qw/Interface Decl Annotated/
  , [as => 'SpecParser'];

# % parser=./Lite/LanguageServer/SpecParser.pm
# % ./Lite/LanguageServer/Spec2Types.pm --output=indented make_spec_from  "$(
# $parser extract_codeblock typescript $specFn|
# $parser cli_xargs_json extract_statement_list|
# grep -v 'interface ParameterInformation'|
# $parser cli_xargs_json --slurp tokenize_statement_list|
# $parser --flatten=0 cli_xargs_json --slurp parse_statement_list
# )" Message
# 'Message'
# [
#   [
#     'fields',
#     'jsonrpc'
#   ]
# ]

use MOP4Import::Types
  CollectedItem => [[fields => qw/name spec fields parent subtypes dependency/]];

sub make_typedefs_from {
  (my MY $self, my ($specDictOrArrayOrFile, @names)) = @_;
  my $specDict = $self->specdict_from($specDictOrArrayOrFile);
  my $collectedDict = $self->collect_spec_from($specDict, @names);
  my %seen;
  my @result = map {
    my CollectedItem $item = $_;
    if ($seen{$item->{name}}++) {
      ()
    } else {
      $self->typedefs_of_collected_item($item, \%seen);
    }
  } $self->reorder_collected_items($collectedDict);
  wantarray ? @result : \@result;
}

sub reorder_collected_items {
  (my MY $self, my ($collectedDict)) = @_;
  my (@result, %seen, $lastKeys);
  $lastKeys = keys %$collectedDict;
  while (keys %$collectedDict) {
    my @ready = grep {
      my CollectedItem $item = $collectedDict->{$_};
      not $item->{parent}
        or $seen{$item->{parent}};
    } keys %$collectedDict;
    push @result, map {
      delete $collectedDict->{$seen{$_} = $_};
    } @ready;
    if ($lastKeys == keys %$collectedDict) {
      die "Can't reorder types. Possibly circular deps? "
        . MOP4Import::Util::terse_dump([remains => sort keys %$collectedDict]
                                       , [ok => @result]);
    }
    $lastKeys = keys %$collectedDict;
  }
  @result;
}

sub collect_spec_from {
  (my MY $self, my ($specDictOrArrayOrFile, @names)) = @_;
  my $specDict = $self->specdict_from($specDictOrArrayOrFile);
  my $collectedDict = {};
  foreach my $name (@names) {
    $self->spec_dependency_of($name, $specDict, $collectedDict);
  }
  $collectedDict;
}

sub spec_dependency_of {
  (my MY $self, my ($declOrName, $specDictOrArrayOrFile, $collectedDict, $opts)) = @_;
  $collectedDict //= {};
  my $specDict = $self->specdict_from($specDictOrArrayOrFile);
  my Decl $decl = ref $declOrName ? $declOrName : $specDict->{$declOrName};
  my $sub = $self->can("spec_dependency_of__$decl->{kind}") or do {
    print STDERR "Not yet supported find spec_dependency: $decl->{kind}"
      . MOP4Import::Util::terse_dump($decl), "\n" unless $self->{quiet};
    return;
  };
  my CollectedItem $item = $collectedDict->{$decl->{name}}
    //= $sub->($self, $decl, $specDict, $collectedDict, $opts);

  wantarray ? ($item, $collectedDict) : $item;
}

sub spec_dependency_of__interface {
  (my MY $self, my Interface $decl, my ($specDictOrArrayOrFile, $collectedDict, $opts)) = @_;
  $collectedDict //= {};
  my $specDict = $self->specdict_from($specDictOrArrayOrFile);
  my CollectedItem $from = $self->intern_collected_item_in($collectedDict, $decl);
  if (my $nm = $decl->{extends}) {
    $from->{parent} = $nm;
    my Decl $superSpec = $specDict->{$nm}
      or Carp::croak "Unknown base type for $decl->{name}: $nm";
    my CollectedItem $superItem
      = $self->spec_dependency_of($superSpec, $specDict, $collectedDict, $opts);
    push @{$superItem->{subtypes}}, $from;
  }
  foreach my Annotated $slot (@{$decl->{body}}) {
    next if ref $slot eq 'HASH' and $slot->{deprecated};
    my $slotDesc = ref $slot eq 'HASH' ? $slot->{body} : $slot;
    my ($slotName, @typeUnion) = @$slotDesc;
    $slotName =~ s/\?\z//;
    push @{$from->{fields}}, do {
      if ($self->{with_field_docs} and ref $slot eq 'HASH') {
        [$slotName, doc => $slot->{comment}]
      } else {
        $slotName;
      }
    };
    foreach my $typeExprString (@typeUnion) {
      $typeExprString =~ /[A-Z]/
        or next;
      my Decl $typeSpec = $specDict->{$typeExprString}
        or next;
      $from->{dependency}{$typeExprString}
        //= $self->spec_dependency_of($typeSpec, $specDict, $collectedDict, $opts);
    }
  }
  $from;
}

sub intern_collected_item_in {
  (my MY $self, my $collectedDict, my Decl $decl, my $opts) = @_;
  $collectedDict->{$decl->{name}} //= do {
    my CollectedItem $item = {};
    $item->{name} = $decl->{name};
    if ($opts->{spec}) {
      $item->{spec} = $decl;
    }
    $item;
  };
}

sub extract_spec_from {
  (my MY $self, my ($specDictOrArrayOrFile, @names)) = @_;
  my $specDict = $self->specdict_from($specDictOrArrayOrFile);
  map {
    $specDict->{$_}
  } @names;
}

sub specdict_from {
  (my MY $self, my ($specDictOrArrayOrFile)) = @_;
  if (not ref $specDictOrArrayOrFile) {
    $self->gather_by_name(
      $self->SpecParser->new->parse_files($specDictOrArrayOrFile)
    );
  } elsif (ref $specDictOrArrayOrFile eq 'ARRAY') {
    $self->gather_by_name(
      @$specDictOrArrayOrFile
    );
  } elsif (ref $specDictOrArrayOrFile eq 'HASH') {
    $specDictOrArrayOrFile;
  } else {
    Carp::croak "Unsupported specDict: "
      . MOP4Import::Util::terse_dump($specDictOrArrayOrFile);
  }
}

sub typedefs_of_collected_item {
  (my MY $self, my CollectedItem $item, my $seen) = @_;
  $seen->{$item->{name}}++;
  # Type is not used currently.
  my @defs = ([fields => @{$item->{fields}}]);
  if ($item->{subtypes}) {
    push @defs, [subtypes => map {
      $self->typedefs_of_collected_item($_, $seen)
    } @{$item->{subtypes}}]
  }
  ($item->{name}, \@defs);
}

sub gather_by_name {
  (my MY $self, my @decls) = @_;
  my %dict;
  foreach my Interface $if (@decls) {
    next unless ref $if eq 'HASH';
    $dict{$if->{name}} = $if;
  }
  \%dict;
}

MY->run(\@ARGV) unless caller;

1;
