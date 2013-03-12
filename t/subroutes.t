#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}
use base qw(File::Spec);
use File::Basename;

use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
my $libdir;
BEGIN {
  unless (grep {$_ eq 'YATT'} MY->splitdir($FindBin::Bin)) {
    die "Can't find YATT in runtime path: $FindBin::Bin\n";
  }
  $libdir = dirname(dirname(untaint_any($FindBin::Bin)));
}
use lib $libdir;
#----------------------------------------

use Test::More qw(no_plan);
use YATT::Lite::Test::TestUtil;
use YATT::Lite::Breakpoint ();

my $CLASS = 'YATT::Lite::WebMVC0::SubRoutes';

require_ok($CLASS);

{
  my $results_params = sub {
    my ($pattern, @expect_params) = @_;
    my ($re, @got_params) = $CLASS->parse_pattern($pattern);
    is_deeply(\@got_params, \@expect_params, "params: $pattern");
  };

  $results_params->('/');
  $results_params->('/blog');
  $results_params->('/blog/:uid', ['uid']);
  $results_params->('/:uid',      ['uid']);


  $results_params->('/authors');
  $results_params->('/authors/:id'
		    , ['id']);
  $results_params->('/authors/:id/edit'
		    , ['id']);

  $results_params->('/articles/:article_id/comments'
		    , ['article_id']);
  $results_params->('/articles/:article_id/comments/:id'
		    , ['article_id'], ['id']);
  $results_params->('/articles/:article_id/comments/:id/edit'
		    , ['article_id'], ['id']);


  $results_params->("/{controller}/{action}/{id}"
		    , ['controller'], ['action'], ['id']);

  $results_params->('/blog/{year}/{month}'
		    , ['year'], ['month']);
  $results_params->('/blog/{year:[0-9]+}/{month:[0-9]{2}}'
		    , ['year'], ['month']);
  $results_params->('/blog/{year:\d+}/{month:\d{2}}'
		    , ['year'], ['month']);

  $results_params->('/blog/{year}-{month}'
		    , ['year'], ['month']);

}

{
  my $builder = sub {
    my $obj = $CLASS->new;
    $obj->append(map {$obj->create(@$_)} @_);
    sub {
      my ($path, $expect) = @_;
      is_deeply [$obj->match($path)], $expect, "match: $path => $expect->[0]";
    };
  };

  my $t;
  $t = $builder->(['/' => 'ROOT']
		  , [[article_list => '/articles']]
		  , [[show_article => '/article/:id']]
		  , [[article_comment => '/article/:article_id/comment/:id']]
		  , [[blog_archive => '/blog/{year:[0-9]+}-{month:[0-9]{2}}']]
		  , [[blog_other   => '/blog/{other}']]
		 );

  $t->("/"
       , [ROOT => []
	  => []]);

  $t->("/article/foo"
       , [show_article => [['id']]
	  => ['foo']]);

  $t->("/article/1234/comment/5678"
       , [article_comment => [['article_id'], ['id']]
	  => [1234, 5678]]);

  $t->("/blog/2001-01"
       , [blog_archive    => [['year'], ['month']]
	  => [2001, '01']]);

  $t->("/blog/foobar"
       , [blog_other      => [['other']]
	  => ['foobar']]);
}
