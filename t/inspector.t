#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin;
use File::Basename qw(dirname);
BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test::More;

require_ok('YATT::Lite::Inspector');

{
  my $test = sub {
    my ($before, $changeList, $expect, $title) = @_;
    my $got = YATT::Lite::Inspector->apply_all_change_to_lines($before, $changeList);
    is_deeply($got, $expect, $title);
  };

  $test->(
    ["foo", "bar"],
    [{"range" =>
      {"end" => {"character" => 0,"line" => 0}
       ,"start" => {"character" => 0,"line" => 0}}
      ,"rangeLength" => 0,"text" => "\n"}],
    ["", "foo", "bar"],
    "insert first newline"
  );

  $test->(
    ["foo", "bar"],
    [{"range" =>
      {"end" => {"character" => 0,"line" => 1}
       ,"start" => {"character" => 3,"line" => 0}}
      ,"rangeLength" => 0,"text" => "\nqux\nquuux"}],
    ["foo", "qux", "quuuxbar"],
    "insert multiline changes with newlines"
  );

  $test->(
    [qw(foo bar baz qux quux)],
    [
      {
        'range' => {
          'end' => { 'character' => 3, 'line' => 1, },
          'start' => { 'character' => 0, 'line' => 1, },
        },
        'rangeLength' => 3, 'text' => '',
      },
      {
        'range' => {
          'end' => { 'character' => 0, 'line' => 2, },
          'start' => { 'character' => 0, 'line' => 1, },
        },
        'rangeLength' => 1, 'text' => '',
      },
      {
        'range' => {
          'end' => { 'character' => 3, 'line' => 2, },
          'start' => { 'character' => 0, 'line' => 2, },
        },
        'rangeLength' => 3, 'text' => '',
      },
      {
        'range' => {
          'end' => { 'character' => 0, 'line' => 3, },
          'start' => { 'character' => 0, 'line' => 2, },
        },
        'rangeLength' => 1, 'text' => '',
      },
    ],
    [qw(foo baz quux)],
    "delete 2nd and 4th lines"
  );

}

# Widget completion tests
SKIP: {
  my $base_dir = dirname($FindBin::Bin);
  my $dir = "$base_dir/samples/basic/1";
  skip "Sample directory not found", 11 unless -d $dir;
  
  my $inspector;
  eval {
    $inspector = YATT::Lite::Inspector->new(dir => $dir);
  };
  skip "Can't create inspector: $@", 11 if $@;
  
  # Test macro widget completion
  {
    my @items = $inspector->complete_widgets("html/index.yatt", "yatt", "");
    my @macros = grep { $_->{kind} == 9 } @items; # SymbolKind__Constructor = 9
    ok(@macros > 0, "Should have macro widgets");
    
    my ($foreach) = grep { $_->{label} eq 'foreach' } @macros;
    ok($foreach, "Should find 'foreach' macro");
    is($foreach->{detail}, "macro yatt:foreach", "foreach detail should be correct");
  }
  
  # Test widget completion with prefix 'e'
  {
    my @items = $inspector->complete_widgets("html/index.yatt", "yatt", "e");
    my ($envelope) = grep { $_->{label} eq 'envelope' } @items;
    ok($envelope, "Should find 'envelope' widget");
    is($envelope->{detail}, "template yatt:envelope (default widget)", "envelope detail should be correct");
    like($envelope->{documentation}, qr/title: html/, "envelope should have title argument");
    like($envelope->{documentation}, qr/body: code/, "envelope should have body argument");
  }
  
  # Test widget completion from foobar.yatt
  {
    my @items = $inspector->complete_widgets("html/foobar.yatt", "yatt", "f");
    
    my ($foreach) = grep { $_->{label} eq 'foreach' } @items;
    ok($foreach, "Should find 'foreach' macro from foobar.yatt");
    
    my ($foo) = grep { $_->{label} eq 'foo' } @items;
    ok($foo, "Should find 'foo' widget in the same file");
    is($foo->{detail}, "widget yatt:foo", "foo detail should be correct");
    like($foo->{documentation}, qr/a: text/, "foo should have 'a' argument");
    like($foo->{documentation}, qr/body: code/, "foo should have body argument");
  }
}

done_testing();

