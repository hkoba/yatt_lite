#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#
# GH-275: Inspector go-to-definition (locate_symbol_at_file_position +
# lookup_symbol_definition) against a tempdir fixture.
#
#  - widget in the same file / another file / via <!yatt:base>
#  - widget argument, <yatt:my> variable: Location must be a real Range
#    (not a Position) with the uri of the declaring file
#  - entity function in <!yatt:entity> and in .htyattrc.pl (0-based line)
#  - cursor on plain text, past EOF, last line: undef, never croak
#  - the site path contains a space and non-ascii chars
#
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test::More;
use File::Temp qw(tempdir);

use YATT::t::t_preload; # To make Devel::Cover happy.

use YATT::Lite::Util qw(untaint_any);
use YATT::Lite::Util::File qw(mkfile_may_wait);

BEGIN {
  foreach my $req (qw(Plack Plack::Response Hash::MultiValue
                      File::AddInc MOP4Import::Base::CLI_JSON Text::Glob)) {
    unless (eval qq{require $req;}) {
      plan skip_all => "$req is not installed."; exit;
    }
  }
  unless (eval {require YATT::Lite::Inspector}) {
    plan skip_all => "YATT::Lite::Inspector is not loadable: $@"; exit;
  }
}

use URI::file;

my $TMP = tempdir(CLEANUP => $ENV{NO_CLEANUP} ? 0 : 1);
END {
  chdir('/');
}

#========================================
# Fixture (bare dir, no app.psgi). The path has a space and non-ascii
# octets so that uri <-> path conversion is exercised. GH-275
#========================================
my $site = untaint_any("$TMP/site with space/\xe3\x81\x82");

my $index_text = <<'END';
<!yatt:base file="base.ytmpl">
<!yatt:args x y="text?">
<h2>&yatt:x;</h2>
<yatt:foo a=y/>
<yatt:other:bar/>
<yatt:frombase/>
<yatt:my v="hello"/>
<yatt:my w:list="1,2"/>
&yatt:v; &yatt:w[0];
&yatt:ent();
&yatt:rcent();
plain text

<!yatt:widget foo a>
<h3>&yatt:a;</h3>

<!yatt:entity ent>
"ent";
END

my $other_text = <<'END';
<!yatt:widget bar z>
&yatt:z;
END

my $base_text = <<'END';
<!yatt:widget frombase>
FROM BASE
END

my $rc_text = <<'END';
use strict;
use YATT::Lite qw(Entity);

Entity rcent => sub {
  "rc";
};
END

MY->mkfile_may_wait
  ("$site/index.yatt", $index_text
   , "$site/other.yatt", $other_text
   , "$site/base.ytmpl", $base_text
   , "$site/.htyattrc.pl", $rc_text);

my $index = "$site/index.yatt";
my $other = "$site/other.yatt";
my $base = "$site/base.ytmpl";

#========================================
# Helpers
#========================================

# (0-based line, char) of the first occurrence of $needle in $text,
# shifted by $inner chars.
sub pos_of {
  my ($text, $needle, $inner) = @_;
  my $off = index($text, $needle);
  die "no such text: $needle" if $off < 0;
  $off += $inner // 0;
  my $pre = substr($text, 0, $off);
  my $line = ($pre =~ tr/\n//);
  my $col = $off - (rindex($pre, "\n") + 1);
  ($line, $col);
}

sub line_of { (pos_of(@_))[0] }

sub uri_of { URI::file->new_abs($_[0])->as_string }

my $ins = YATT::Lite::Inspector->new(dir => $site);

sub definition_at {
  my ($file, $line, $col) = @_;
  my ($sym, $cursor) = $ins->locate_symbol_at_file_position($file, $line, $col)
    or return undef;
  my $loc = $ins->lookup_symbol_definition($sym, $cursor);
  $loc;
}

sub definition_of {
  my ($file, $text, $needle, $inner) = @_;
  definition_at($file, pos_of($text, $needle, $inner));
}

sub is_location {
  my ($got, $uri, $start_line, $start_char, $title) = @_;
  subtest $title, sub {
    ok $got, "found" or return;
    is $got->{uri}, $uri, "uri";
    is_deeply $got->{range}{start}
      , {line => $start_line, character => $start_char}, "range.start";
    ok ref $got->{range}{end} eq 'HASH' && defined $got->{range}{end}{line}
      , "range.end is a Position (range is a Range, not a Position)";
  };
}

#========================================
# Widgets
#========================================

is_location(definition_of($index, $index_text, '<yatt:foo', 6)
            , uri_of($index), line_of($index_text, '<!yatt:widget foo'), 0
            , "<yatt:foo> -> <!yatt:widget foo> in the same file");

is_location(definition_of($index, $index_text, '<yatt:other:bar', 12)
            , uri_of($other), 0, 0
            , "<yatt:other:bar> -> other.yatt");

is_location(definition_of($index, $index_text, '<yatt:frombase', 8)
            , uri_of($base), 0, 0
            , "<yatt:frombase> -> base.ytmpl via <!yatt:base>");

#========================================
# Arguments: Range must start at the argument token of the declaration
#========================================

is_location(definition_of($index, $index_text, '&yatt:x;', 6)
            , uri_of($index), pos_of($index_text, '<!yatt:args x', 12)
            , "&yatt:x; -> 'x' in <!yatt:args x ...>");

is_location(definition_of($index, $index_text, '&yatt:a;', 6)
            , uri_of($index), pos_of($index_text, '<!yatt:widget foo a', 18)
            , "&yatt:a; -> 'a' in <!yatt:widget foo a>");

is_location(definition_of($other, $other_text, '&yatt:z;', 6)
            , uri_of($other), pos_of($other_text, '<!yatt:widget bar z', 18)
            , "&yatt:z; -> 'z' in <!yatt:widget bar z> (first line)");

#========================================
# <yatt:my> variables
#========================================

is_location(definition_of($index, $index_text, '&yatt:v;', 6)
            , uri_of($index), pos_of($index_text, '<yatt:my v=', 9)
            , "&yatt:v; -> <yatt:my v=...>");

{
  my $loc = definition_of($index, $index_text, '&yatt:w[0];', 6);
  my ($line, $col) = pos_of($index_text, '<yatt:my w:list', 9);
  is_location($loc, uri_of($index), $line, $col
              , "&yatt:w[0]; -> <yatt:my w:list=...>");
  is_deeply $loc && $loc->{range}{end}
    , {line => $line, character => $col + length('w:list')}
    , "symbol_range covers 'w:list' (name:type path)";
}

#========================================
# Entity functions
#========================================

is_location(definition_of($index, $index_text, '&yatt:ent();', 6)
            , uri_of($index), line_of($index_text, '<!yatt:entity ent'), 0
            , "&yatt:ent() -> <!yatt:entity ent>");

{
  my $loc = definition_of($index, $index_text, '&yatt:rcent();', 6);
  ok $loc, "&yatt:rcent() found";
  like $loc->{uri}, qr{/\.htyattrc\.pl\z}, "-> .htyattrc.pl";
  # Sub::Identify reports the first statement of the sub (1-based).
  is $loc->{range}{start}{line}, line_of($rc_text, '"rc";')
    , "0-based line of the first statement of entity_rcent";
}

#========================================
# Never croak
#========================================

{
  my $nlines = () = $index_text =~ /\n/g;
  foreach my $case ([pos_of($index_text, 'plain text', 3), "plain text"]
                    , [$nlines - 1, 3, "last line, col > 0"]
                    , [$nlines, 5, "line == number of newlines, col > 0"]
                    , [99, 0, "line past EOF"]) {
    my ($line, $col, $title) = @$case;
    my $got = eval { definition_at($index, $line, $col) };
    is $@, '', "no exception: $title (line=$line col=$col)";
    is $got, undef, "undef: $title";
  }
}

done_testing();
