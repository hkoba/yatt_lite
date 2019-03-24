#!/usr/bin/env perl
package YATT::Lite::LanguageServer::Spec2Types;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base
  , [output_format => indented => sub {
    my ($self, $outFH, @items) = @_;
    require Data::Dumper;
    foreach my $item (@items) {
      print $outFH Data::Dumper->new($item)->Indent(1)->Terse(1)->Dump, "\n";
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


sub make_typedefs_from {
  (my MY $self, my ($specDictOrArrayOrFile, @names)) = @_;
  my $specDict = $self->specdict_from($specDictOrArrayOrFile);
  map {
    my Decl $decl = $specDict->{$_};
    if (my $sub = $self->can("spec_of__$decl->{kind}")) {
      $sub->($self, $decl, $specDict);
    } else {
      ();
    }
  } @names;
}

use MOP4Import::Types
  CollectedItem => [[fields => qw/name spec fields dependency/]];

sub spec_dependency_of {
  (my MY $self, my ($declOrName, $specDictOrArrayOrFile, $collectedDict, $opts)) = @_;
  my $specDict = $self->specdict_from($specDictOrArrayOrFile);
  my Decl $decl = ref $declOrName ? $declOrName : $specDict->{$declOrName};
  my $sub = $self->can("spec_dependency_of__$decl->{kind}") or do {
    print STDERR "Not yet supported find spec_dependency: $decl->{kind}"
      . MOP4Import::Util::terse_dump($decl), "\n" unless $self->{quiet};
    return;
  };
  $sub->($self, $decl, $specDict, $collectedDict, $opts)
}

sub spec_dependency_of__interface {
  (my MY $self, my Interface $decl, my ($specDictOrArrayOrFile, $collectedDict, $opts)) = @_;
  $collectedDict //= {};
  my $specDict = $self->specdict_from($specDictOrArrayOrFile);
  my CollectedItem $from = $self->intern_collected_item_in($collectedDict, $decl);
  if (my $nm = $decl->{extends}) {
    my Decl $super = $specDict->{$nm}
      or Carp::croak "Unknown base type for $decl->{name}: $nm";
    $from->{dependency}{$nm} = $self->intern_collected_item_in($collectedDict, $super, $opts);
  }
  foreach my Annotated $slot (@{$decl->{body}}) {
    my $slotDesc = ref $slot eq 'HASH' ? $slot->{body} : $slot;
    unless (ref $slotDesc eq 'ARRAY') {
      die "reall";
    }
    my ($slotName, @typeUnion) = @$slotDesc;
    $slotName =~ s/\?\z//;
    push @{$from->{fields}}, (ref $slot eq 'HASH' ? [$slotName, doc => $slot->{comment}]
                              : $slotName);
    foreach my $typeExprString (@typeUnion) {
      $typeExprString =~ /[A-Z]/
        or next;
      my Decl $typeSpec = $specDict->{$typeExprString}
        or next;
      $from->{dependency}{$typeExprString}
        //= $self->spec_dependency_of($typeSpec, $specDict, $collectedDict, $opts);
    }
  }
  wantarray ? ($from, $collectedDict) : $from;
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

sub spec_of__interface {
  (my MY $self, my Interface $if, my $specDict) = @_;
  # Type is not used currently.
  my @spec = [fields => map {
    my Decl $slotDecl = $_;
    if (ref $slotDecl eq 'ARRAY') {
      my ($name, @typeunion) = @$slotDecl;
      $name;
    } elsif ($slotDecl->{kind}) {
      Carp::croak "Not implemented for interface body: $slotDecl->{kind}";
    } elsif ($slotDecl->{deprecated}) {
      ();
    } else {
      my $name = $slotDecl->{body}[0];
      $name =~ s/\?\z//;
      if ($slotDecl->{comment}) {
        [$name => doc => $slotDecl->{comment}];
      } else {
        $name
      }
    }
  } @{$if->{body}}];
  if ($if->{extends}) {
    my ($superName, $superSpec)
      = $self->spec_of__interface($specDict->{$if->{extends}}, $specDict);
    ($superName, [@$superSpec, [subtypes => $if->{name}, \@spec]]);
  } else {
    ($if->{name}, \@spec);
  }
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
