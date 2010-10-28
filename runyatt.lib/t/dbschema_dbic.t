#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use Test::More;
use Test::Differences;

sub untaint_any {$_[0] =~ m{(.*)} and $1}
use FindBin;
use lib untaint_any("$FindBin::Bin/..");

foreach my $req (qw(DBD::SQLite DBIx::Class SQL::Abstract)) {
  unless (eval qq{require $req}) {
    plan skip_all => "$req is not installed."; exit;
  }
}
plan qw(no_plan);

my $DBNAME = shift || ':memory:';

{
  my $CLASS = 'MyDB1';
  package MyDB1;
  use YATT::Lite::DBSchema::DBIC
    (__PACKAGE__, verbose => $ENV{DEBUG_DBSCHEMA}
     , [Author => undef
	, author_id => [int => -primary_key, -autoincrement
			, ['has_many:books:author_id'
			   => [Book => undef
			       , book_id => [int => -primary_key
					     , -autoincrement]
			       , author_id => [int => -indexed
					       , [belongs_to => 'Author']]
			       , name => 'text']]]
	, name => 'text']);

# -- MyDB1::Result::Author->has_many(books, MyDB1::Result::Book, author_id)
# -- MyDB1::Result::Book->belongs_to(Author, MyDB1::Result::Author, author_id)

  package main;
  my $schema = $CLASS->connect("dbi:SQLite:dbname=$DBNAME");
  $schema->YATT_DBSchema->deploy;

  ok my $author = $schema->resultset('Author'), "resultset Author";
  ok my $book = $schema->resultset('Book'), "resultset Book";

  is((my $foo = $author->create({name => 'Foo'}))->id
     , 1, "Author create name=Foo");

  is $book->create({name => "Foo's 1st book", author_id => $foo->id})->id
    , 1, "Book create Foo's 1st";

  is $foo->create_related(books => {name => "Foo's 2nd book"})->id
    , 2, "Book create Foo's 2nd";

  is((my $bar = $author->create({name => 'Bar'}))->id
     , 2, "Author create name=Bar");

  is $book->create({name => "Bar's 1st book", author_id => $bar->id})->id
    , 3, "Book create Bar 1st";

  is $author->count, 2, "Total number of authors";

  is $book->count, 3, "Total number of books";

  is_deeply [sort map {$_->name} $foo->search_related('books')->all]
    , ["Foo's 1st book", "Foo's 2nd book"]
      , "Foo's books: foo->search_rel";
  # print $_->name(), "\n" for $foo->search_related('books');
  #is $author->search_related(books => {name => 'Foo'})->count
  #  , 2, "Foo's books: author->search_rel";
  is $author->search_related(books => {'me.name' => 'Foo'})->count
    , 2, "Foo's books: author->search_rel";
}

{
  my $CLASS = 'MyDB2';
  package MyDB2;
  use YATT::Lite::DBSchema::DBIC
    (__PACKAGE__, verbose => $ENV{DEBUG_DBSCHEMA}
     , [User => undef
	, uid => [integer => -primary_key]
	, fname => 'text'
	, lname => 'text'
	, email => 'text'
	, encpass => 'text'
	, tmppass => 'text'
	, [-has_many
	   , [Address => undef
	    , addrid => [integer => -primary_key]
	    , owner =>  [int => [belongs_to => 'User', 'owner']]
	    , country => 'text'
	    , zip => 'text'
	    , prefecture => 'text'
	    , city => 'text'
	    , address => 'text']]
	, [-has_many
	   , [Entry => undef
	      , eid => [integer => -primary_key]
	      , owner => [int => [belongs_to => 'User', 'owner']]
	      , title => 'text'
	      , text  => 'text']]
       ]);

  package main;
  my $schema = $CLASS->connect("dbi:SQLite:dbname=$DBNAME");
  $schema->YATT_DBSchema->deploy;

  ok my $user = $schema->resultset('User'), "resultset User";
  ok my $entries = $schema->resultset('Entry'), "resultset Entry";

  is((my $foo = $user->create({fname => 'Foo', lname => 'Bar'}))->id
     , 1, "User.create.id");

  is($entries->create({title => 'First entry', text => "Hello world!"
		       , owner => $foo->id})->id
     , 1, "Entry.create.id");
}
