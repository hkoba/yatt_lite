#!/usr/bin/env perl
package YATT::Lite::LanguageServer::SpecParser;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base;

use MOP4Import::Types
  (Decl => [[fields => qw/kind name body exported/]
            , [subtypes =>
               Interface => [[fields => qw/extends/]]
             ]]);

sub parse_declarator {
  (my MY $self, my $declTok) = @_;
  my Decl $decl = {};
  if ($self->match_token(export => $declTok)) {
    $decl->{exported} = 1;
  }
  $decl->{kind} = shift @$declTok;
  $decl->{name} = shift @$declTok;
  if ($decl->{kind} eq 'interface') {
    if ($self->match_token(extends => $declTok)) {
      my Interface $if = $decl;
      $if->{extends} = shift @$declTok;
    }
  }
  $decl;
}

sub match_token {
  (my MY $self, my ($tokString, $tokList)) = @_;
  if (@$tokList and $tokList->[0] eq $tokString) {
    shift @$tokList;
  }
}

#----------------------------------------

sub tokenize_statement_list {
  (my MY $self, my $statementList) = @_;
  map {
    my ($declarator, $comment, $body) = @$_;
    [$self->tokenize_declarator($declarator)
     , $self->tokenize_comment_block($comment)
     , $self->tokenize_declbody($body)];
  } @$statementList;
}

sub tokenize_declbody {
  (my MY $self, my $declString) = @_;
  [map {s/\s*\z//; $_}
   grep {/\S/}
   split m{(; | [{}\|] | /\*\*\n(?:.*?)\*/) \s*}xs, $declString];
}

sub tokenize_comment_block {
  (my MY $self, my $commentString) = @_;
  return undef unless defined $commentString;
  unless ($commentString =~ s,^\s*/\*\*\n,,s) {
    Carp::croak "Comment doesn't start with /**\\n: '$commentString";
  }
  unless ($commentString =~ s,\*/\n?\z,,s) {
    Carp::croak "Comment doesn't end with */: '$commentString";
  }
  $commentString =~ s/^\s+\*\ //mg;
  $commentString =~ s/\s+\z//;
  $commentString;
}

sub tokenize_declarator {
  (my MY $self, my $declString) = @_;
  [split " ", $declString];
}

sub extract_statement_list {
  (my MY $self, my ($codeList)) = @_;
  local $_;
  my $wordRe = qr{[^\s{}=\|]+};
  my $groupRe = qr{( \{ (?: (?> [^{}]+) | (?-1) )* \} )}x;
  my $commentRe = qr{/\*\*\n(?:.*?)\*/\n?}sx;
  my $typeElemRe = qr{$wordRe | $groupRe}sx;
  my @result;
  foreach (@$codeList) {
    while (m{
              \G(?<comment>$commentRe)?
              (?<decl>(?:$wordRe\s+)+)
              (?: (?<body> $groupRe )
                | = \s* (?<type>
                    $typeElemRe \s*(?: \| \s*$typeElemRe)*
                  )
                  \s*;
              )
          }sgx) {
      push @result, [$+{decl}, $+{comment}, $+{body} // $+{type}];
    }
  }
  @result;
}

# Lite/LanguageServer/SpecParser.pm --flatten --output=raw extract_codeblock typescript specification.md
sub extract_codeblock {
  (my MY $self, my $langId, local @ARGV) = @_;
  local $_;
  my ($chunk, @result);
  while (<<>>) {
    my $line = s{^```$langId\b}{} .. s{^```}{}
      or next;
    my $end = $line =~ /E0/;
    s/\r//;
    $chunk .= $_ if $line >= 2 and not $end;
    if ($end) {
      push @result, $chunk;
      $chunk = "";
    }
  }
  @result;
}

MY->run(\@ARGV) unless caller;
1;
