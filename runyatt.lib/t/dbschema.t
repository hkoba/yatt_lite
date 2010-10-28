#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use Test::More;
use Test::Differences;

sub untaint_any {$_[0] =~ m{(.*)} and $1}
use FindBin;
use lib untaint_any("$FindBin::Bin/..");

use YATT::Lite::Util qw(terse_dump);

foreach my $req (qw(DBD::SQLite SQL::Abstract)) {
  unless (eval qq{require $req}) {
    plan skip_all => "$req is not installed."; exit;
  }
}
plan qw(no_plan);

my $CLASS = 'YATT::Lite::DBSchema';
use_ok($CLASS);

my $DBNAME = shift || ':memory:';

my @schema1
  = [Author => undef
	, author_id => [int => -primary_key, -autoincrement
			, ['has_many:books:author_id'
			   => [Book => undef
			       , book_id => [int => -primary_key
					     , -autoincrement]
			       , author_id => [int => -indexed
					       , [belongs_to => 'Author']]
			       , name => 'text']]]
	, name => 'text'];

{
  my $THEME = "[schema only]";
  my $schema = $CLASS->new(@schema1);
  is_deeply [$schema->list_tables], [qw(Author Book)]
    , "$THEME list_tables";

  is_deeply [map {ref $_} $schema->list_tables(raw => 1)]
    , [("${CLASS}::Table") x 2]
      , "$THEME list_tables raw=>1";

  is ref $schema->info_table('Author'), "${CLASS}::Table"
    , "$THEME info_table Author";

  is_deeply [map {[$_, $schema->list_table_columns($_)]} $schema->list_tables]
    , [[Author => qw(author_id name)], [Book => qw(book_id author_id name)]]
      , "$THEME list_table_columns";


  is_deeply [$schema->list_relations('Author')]
    , [[has_many => 'books', author_id => 'Book']]
      , "$THEME relations: Author has_many Book";

  is_deeply [$schema->list_relations('Book')]
    , [[belongs_to => 'author', author_id => 'Author']]
      , "$THEME relations: Book belongs_to Author";
}

{
  my $THEME = "[sqlite create]";
  my $dbh = DBI->connect("dbi:SQLite:dbname=$DBNAME", undef, undef
			 , {PrintError => 0, RaiseError => 1, AutoCommit => 0});

  ok(my $schema = $CLASS->new(DBH => $dbh, @schema1)
     , "$THEME Can new without connection spec");

  is_deeply $dbh->selectall_arrayref
    (q|select name from sqlite_master where type = 'table'|)
      , [], "$THEME no table before create";

  eq_or_diff join("", map {chomp;"$_;\n"} $schema->sql_create), <<'END'
CREATE TABLE Author
(author_id integer primary key
, name text);
CREATE TABLE Book
(book_id integer primary key
, author_id int
, name text);
CREATE INDEX Book_author_id on Book(author_id);
END
    , "$THEME SQL returned by sql_create";

  $schema->create(sqlite => $DBNAME);

  is_deeply $schema->dbh->selectall_arrayref
    (q|select name from sqlite_master where type = 'table'|)
      , [['Author'], ['Book']], "$THEME dbschema create worked";
}

{
  my $THEME = "[auto connect/create]";
  ok(my $schema = $CLASS->new(connection_spec => [sqlite => $DBNAME], @schema1)
     , "$THEME Can create");

  is_deeply $schema->dbh->selectall_arrayref
    (q|select name from sqlite_master where type = 'table'|)
      , [['Author'], ['Book']]
	, "$THEME dbschema can connect";
}

{
  my $THEME = "[Relation in column_list]";
  my $schema = $CLASS->new
    ([Author => undef
      , author_id => [int => -primary_key, -autoincrement]
      , name => 'text'
      , [has_many => [Book => undef
		      , book_id => [int => -primary_key, -autoincrement]
		      , author_id => [int => -indexed
				     , [belongs_to => 'Author']]
		      , name => 'text']
	, 'author_id', {join_type => 'left'}]
     ]);

  is_deeply [$schema->list_tables], [qw(Author Book)]
    , "$THEME list_tables";

  is_deeply [map {ref $_} $schema->list_tables(raw => 1)]
    , [("${CLASS}::Table") x 2]
      , "$THEME list_tables raw=>1";

  is ref $schema->info_table('Author'), "${CLASS}::Table"
    , "$THEME info_table Author";

  is_deeply [map {[$_, $schema->list_table_columns($_)]} $schema->list_tables]
    , [[Author => qw(author_id name)], [Book => qw(book_id author_id name)]]
      , "$THEME list_table_columns";

  is_deeply [$schema->list_relations('Author')]
    , [[has_many => 'book', author_id => 'Book']]
      , "$THEME relations: Author has_many Book";

  is_deeply [$schema->list_relations('Book')]
    , [[belongs_to => 'author', author_id => 'Author']]
      , "$THEME relations: Book belongs_to Author";
}

{
  my $THEME = "[Encoded relation]";
  my $schema = $CLASS->new
    ([Book => undef
      , book_id => [int => -primary_key, -autoincrement]
      , author_id => [[Author => undef
		       , author_id => [int => -primary_key, -autoincrement]
		       , name => 'text']]
      , name => 'text']
     );

  is_deeply [$schema->list_tables], [qw(Book Author)]
    , "$THEME list_tables";

  is_deeply [map {ref $_} $schema->list_tables(raw => 1)]
    , [("${CLASS}::Table") x 2]
      , "$THEME list_tables raw=>1";

  is ref $schema->info_table('Author'), "${CLASS}::Table"
    , "$THEME info_table Author";

  is_deeply [map {[$_, $schema->list_table_columns($_)]} $schema->list_tables]
    , [[Book => qw(book_id author_id name)], [Author => qw(author_id name)]]
      , "$THEME list_table_columns";

  is_deeply [$schema->list_relations('Author')]
    , [[has_many => 'book', author_id => 'Book']]
      , "$THEME relations: Author has_many Book";

  is_deeply [$schema->list_relations('Book')]
    , [[belongs_to => 'author', author_id => 'Author']]
      , "$THEME relations: Book belongs_to Author";
}

{
  my $THEME = "[many_to_many]";
  my $schema = $CLASS->new
    ([user => undef
	, id => [integer => -primary_key, -autoincrement]
	, name => 'text'
	, ['has_many:user_address'
	   => [user_address => undef
	       , user => [int => [belongs_to => 'user']]
	       , address => [int => [belongs_to =>
				     [address => undef
				      , id => [int => -primary_key]
				      , street => 'text'
				      , town => 'text'
				      , area_code => 'text'
				      , country => 'text'
				      , ['has_many:user_address' => 'user']
				      , ['many_to_many:users'
					 => 'user_address', 'user']
				     ]]]
	       , [primary_key => qw(user address)]]]
	, ['many_to_many:addresses'
	   => 'user_address', 'address']
       ]);

  # print join("", map {chomp;"$_;\n"} $schema->sql_create), "\n";
  foreach my $tabName (qw(user user_address address)) {
    # print terse_dump($schema->list_relations($tabName)), "\n";
  }
}

{
  my $THEME = "[Misc]";
  my $schema = $CLASS->new
    ([Account => undef
      , aid => [int => -primary_key, -autoincrement]
      , aname => [text => -unique]
      , atype => [text => -indexed]]
     # XXX: Enum(Asset, Liability, Income, Expense)

     , [Description => undef
	, did => [int => -primary_key, -autoincrement]
	, dname => [text => -unique]]

     , [Transaction => undef
	, tid => [int => -primary_key, -autoincrement]
	, at =>  [date => -indexed]
	, debit_id => [['Account']]
	, amt => 'int'
	, credit_id => [['Account']]
	, desc => [['Description'], -indexed]
	, note => 'text'
       ]);

  # print join("", map {chomp;"$_;\n"} $schema->sql_create), "\n";
  # print terse_dump($schema->list_relations('Transaction')), "\n";
  # print terse_dump($schema->list_relations('Account')), "\n";
}
