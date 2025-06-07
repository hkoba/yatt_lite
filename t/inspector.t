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

# Widget and Entity completion tests
SKIP: {
  my $base_dir = dirname($FindBin::Bin);
  my $dir = "$base_dir/samples/basic/1";
  skip "Sample directory not found", 24 unless -d $dir;
  
  my $inspector = YATT::Lite::Inspector->new(dir => $dir);
  
  # Widget completion tests
  
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
  
  # Entity completion tests
  
  # Test entity macro completion
  {
    my @items = $inspector->complete_entities("html/index.yatt", "yatt", "", 0);
    my @macros = grep { $_->{detail} =~ /entity macro/ } @items;
    ok(@macros > 0, "Should have entity macros");
    
    my ($if_macro) = grep { $_->{label} eq 'if' } @macros;
    ok($if_macro, "Should find 'if' entity macro");
    is($if_macro->{detail}, "entity macro yatt:if", "if entity macro detail should be correct");
  }
  
  # Test entity variable completion in default widget
  {
    my @items = $inspector->complete_entities("html/foobar.yatt", "yatt", "", 1);  # Line 2 in editor (0-based: 1)
    my @vars = grep { $_->{kind} == 13 } @items; # SymbolKind__Variable = 13
    ok(@vars > 0, "Should have variables from default widget arguments");
    
    my ($x_var) = grep { $_->{label} eq 'x' } @vars;
    ok($x_var, "Should find 'x' variable");
    is($x_var->{detail}, "var x: text", "variable 'x' detail should be correct");
    
    my ($y_var) = grep { $_->{label} eq 'y' } @vars;
    ok($y_var, "Should find 'y' variable");
    is($y_var->{detail}, "var y: text", "variable 'y' detail should be correct");
  }
  
  # Test entity variable completion in foo widget
  {
    my @items = $inspector->complete_entities("html/foobar.yatt", "yatt", "", 5);  # Line 6 in editor (0-based: 5)
    my @vars = grep { $_->{kind} == 13 } @items;
    
    my ($a_var) = grep { $_->{label} eq 'a' } @vars;
    ok($a_var, "Should find 'a' variable in foo widget");
    is($a_var->{detail}, "var a: text", "variable 'a' detail should be correct");
    
    # Check that x and y are NOT present
    my ($x_var) = grep { $_->{label} eq 'x' } @vars;
    ok(!$x_var, "Should NOT find 'x' variable in foo widget");
  }
  
  # Test entity completion with prefix 'd'
  {
    my @items = $inspector->complete_entities("html/index.yatt", "yatt", "d", 0);
    my ($default) = grep { $_->{label} eq 'default' } @items;
    ok($default, "Should find 'default' entity function");
    is($default->{detail}, "entity yatt:default", "default entity detail should be correct");
  }
}

done_testing();

