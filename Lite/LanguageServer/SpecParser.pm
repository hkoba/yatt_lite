#!/usr/bin/env perl
package YATT::Lite::LanguageServer::SpecParser;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base;

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
  [grep {/\S/} split m{(; | [{}] | /\*\*\n(?:.*?)\*/) \s*}xs, $declString];
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
  my $wordRe = qr{[^\s{}]+};
  my $groupRe = qr{( \{ (?: (?> [^{}]+) | (?-1) )* \} )}x;
  my $commentRe = qr{/\*\*\n(?:.*?)\*/\n?}sx;
  my @result;
  foreach (@$codeList) {
    while (m{
              \G(?<comment>$commentRe)?
              (?<decl>(?:$wordRe\s+)+)
              (?<body> $groupRe )
          }sgx) {
      push @result, [$+{decl}, $+{comment}, $+{body}];
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
