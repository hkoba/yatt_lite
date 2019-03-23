#!/usr/bin/env perl
package YATT::Lite::LanguageServer::SpecParser;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base;

use MOP4Import::Types
  (Annotated => [[fields => qw/comment body/]
                 , [subtypes =>
                    Decl => [[fields => qw/kind name exported/]
                             , [subtypes =>
                                Interface => [[fields => qw/extends/]]
                              ]]
                  ]]
 );

sub parse_statement_list {
  (my MY $self, my $statementTokList) = @_;
  map {
    my ($declarator, $comment, $bodyTokList) = @$_;
    #
    my Decl $decl = $self->parse_declarator($declarator);
    $decl->{comment} = $comment;

    if (my $sub = $self->can("parse_$decl->{kind}_declbody")) {
      $decl->{body} = \ my @body;
      while (@$bodyTokList) {
        push @body, $sub->($self, $decl, $bodyTokList);
      }
      if (@$bodyTokList) {
        Carp::croak "Invalid trailing token(s) for declbody of "
          . MOP4Import::Util::terse_dump($decl). ": "
          . MOP4Import::Util::terse_dump($bodyTokList);
      }
    }

    $decl;

  } @$statementTokList;
}

sub parse_interface_declbody {
  (my MY $self, my Decl $decl, my $bodyTokList) = @_;
  my @result;
  unless ($self->match_token('{', $bodyTokList)) {
    Carp::croak "Invalid leading token for declbody of "
      . MOP4Import::Util::terse_dump($decl). ": "
      . MOP4Import::Util::terse_dump($bodyTokList);
  }
  my Annotated $ast;
  while (@$bodyTokList and $bodyTokList->[0] ne '}') {
    my $tok = shift @$bodyTokList;
    if ($tok eq '{') {
      $ast->{body} = [$self->parse_interface_declbody($decl, $bodyTokList)];
    } elsif ($tok =~ m{^/\*\*}) {
      $ast->{comment} = $self->tokenize_comment_block($tok);
    } elsif ($tok =~ s{^(?<slotName>(?:\w+ |\[[^]]+\]) \??):\s*}{}x) {
      # slot
      $ast->{body} = my $slotDef = [$+{slotName}];
      unshift @$bodyTokList, $tok if $tok =~ /\S/;
      push @$slotDef, $self->parse_typeunion($decl, $bodyTokList);
      push @result, defined $ast->{comment} ? $ast : $ast->{body};
      undef $ast;
    } else {
      die "HOEHOE? "
        .MOP4Import::Util::terse_dump($bodyTokList, [decl => $decl]);
    }
  }
  unless ($self->match_token('}', $bodyTokList)) {
    Carp::croak "Invalid closing token for declbody of "
      . MOP4Import::Util::terse_dump($decl). ": "
      . MOP4Import::Util::terse_dump($bodyTokList);
  }

  # optional
  $self->match_token(';', $bodyTokList);

  # I'm not sure why this.
  # Found after TextDocumentClientCapabilities.completion.completionItemKind
  $self->match_token(',', $bodyTokList);

  if (defined $ast) {
    Carp::croak "Something went wrong for declbody of "
      . MOP4Import::Util::terse_dump($decl). ": "
      . MOP4Import::Util::terse_dump($ast);
  }
  @result;
}

# typeunion -> typeconj -> typeunion

sub parse_typeunion {
  (my MY $self, my Decl $decl, my $bodyTokList) = @_;
  my @union;
  while (@$bodyTokList and $bodyTokList->[0] ne ';') {
    if ($bodyTokList->[0] eq '{') {
      push @union, $self->parse_interface_declbody($decl, $bodyTokList);
    } else {
      push @union, $self->parse_typeconj($decl, $bodyTokList);
      if ($self->match_token(';', $bodyTokList)) {
        last;
      }
    }
    if (not $self->match_token('|', $bodyTokList)) {
      last;
    }
  }
  @union;
}

#
# parse conjunctive? type expression.
#
sub parse_typeconj {
  (my MY $self, my Decl $decl, my $bodyTokList) = @_;
  if (my ($ident, $bracket) = $bodyTokList->[0] =~ /^(\w+(?:<[^>]+>)?)(\[\])?\z/) {
    shift @$bodyTokList;
    return defined $bracket ? [$ident, $bracket] : $ident;
  } elsif (my ($string) = $bodyTokList->[0] =~ /^('[^']*' | "[^"]*" )\z/x) {
    shift @$bodyTokList;
    return [constant => $string];
  } elsif ($self->match_token('(', $bodyTokList)) {
    my $expr = [\ my @union];
    until ($self->match_token(')', $bodyTokList)) {
      do {
        push @union, $self->parse_typeconj($decl, $bodyTokList);
      } while ($self->match_token('|', $bodyTokList));
    }
    if (my $bracket = $self->match_token('[]', $bodyTokList)) {
      push @$expr, $bracket;
    }
    return $expr;
  } else {
    die "Really? ".MOP4Import::Util::terse_dump($bodyTokList, [decl => $decl]);
  }
}

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
   split m{(; | [{}()\|] | /\*\*\n(?:.*?)\*/) \s*}xs, $declString];
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
  my $commentRe = qr{/\*\*\n(?:.*?)\*/\n?}sx;
  my $groupRe = qr{( \{ (?: (?> [^{}/]+) | $commentRe | /[^\*] | (?-1) )* \} )}x;
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
