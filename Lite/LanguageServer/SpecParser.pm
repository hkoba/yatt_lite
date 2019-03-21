#!/usr/bin/env perl
package YATT::Lite::LanguageServer::SpecParser;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base;

sub extract_statement_list {
  (my MY $self, my ($codeList)) = @_;
  local $_;
  my $wordRe = qr{[^\s{}]};
  my $groupRe = qr{( \{ (?: (?> [^{}]+) | (?-1) )* \} )}x;
  my $commentRe = qr{/\*\*\n(?:.*?)\*/\n?}sx;
  my @result;
  foreach (@$codeList) {
    while (m{
              \G(?<comment>$commentRe)?
              (?<decl>(?:$wordRe+\s+)+)
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
