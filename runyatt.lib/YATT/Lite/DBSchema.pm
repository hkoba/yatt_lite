package YATT::Lite::DBSchema; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use Carp;
use File::Basename;

use base qw(YATT::Lite::Object);
use fields (qw(table_list table_dict dbtype cf_DBH
	       cf_user
	       cf_auth
	       cf_connection_spec
	       cf_verbose
	       cf_dbtype
	       cf_NULL
	       cf_name
	       cf_no_header
	       cf_auto_create
	       cf_as_base
	       cf_coltype_map

	       cf_after_dbinit
	       cf_group_writable
	     ));

use YATT::Lite::Types
  ([Item => fields => [qw(not_configured
			  cf_name)]
    , [Table => fields => [qw(pk chk_unique
			      chk_index chk_check
			      col_list col_dict
			      relationSpec
			      reference_dict)]]
    , [Column => fields => [qw(cf_type
			       cf_hidden
			       cf_unique
			       cf_indexed
			       cf_primary_key
			       cf_autoincrement
			     )]]]

   , [QBuilder => fields => [qw(selects joins)]]
);

use YATT::Lite::Util qw(coalesce globref ckeval terse_dump lexpand);

#========================================
# Class Hierarchy in case of 'package YourSchema; use YATT::Lite::DBSchema':
#
#   YATT::Lite::DBSchema (or its subclass)
#    ↑
#   YourSchema
#

#========================================
sub DESTROY {
  my MY $schema = shift;
  if ($schema->{cf_DBH}) {
    # XXX: sqlite specific commit.
    $schema->{cf_DBH}->commit;
  }
}

#========================================

sub new {
  my $pack = shift;
  $pack->parse_import(\@_, \ my %opts);
  my MY $self = $pack->SUPER::new(%opts);
  foreach my $item (@_) {
    if (ref $item) {
      $self->get_table(@$item);
    } else {
      croak "Invalid schema item: $item";
    }
  }
  $self->verify_schema;
  $self;
}

sub parse_import {
  my ($pack, $list, $opts) = @_;
  # -bool_flag
  # key => value
  for (; @$list; shift @$list) {
    last if ref $list->[0];
    if ($list->[0] =~ /^-(\w+)/) {
      $opts->{$1} = 1;
    } else {
      croak "Option value is missing for $list->[0]"
	unless @$list >= 2;
      $opts->{$list->[0]} = $list->[1];
      shift @$list;
    }
  }
}

#########################################
sub after_connect {
  my MY $self = shift;
  $self->ensure_created_on($self->{cf_DBH}) if $self->{cf_auto_create};
}

sub dbinit_sqlite {
  (my MY $self, my $sqlite_fn) = @_;
  chmod 0664, $sqlite_fn if $self->{cf_group_writable} // 1;
}

#========================================

sub has_connection {
  my MY $schema = shift;
  $schema->{cf_DBH}
}

sub dbh {
  (my MY $schema, my $spec) = @_;
  unless ($schema->{cf_DBH}) {
    unless (defined ($spec ||= $schema->{cf_connection_spec})) {
      croak "connection_spec is empty";
    }
    if (ref $spec eq 'ARRAY') {
      $schema->connect_to(@$spec);
    } elsif (ref $spec eq 'CODE') {
      $schema->{cf_DBH} = $spec->($schema);
    } else {
      croak "Unknown connection spec obj: $spec";
    }
  };

  $schema->{cf_DBH}
}

sub connect_to {
  (my MY $schema, my ($dbtype, @args)) = @_;
  if ($dbtype =~ /^dbi:(\w+):/i) {
    $schema->connect_to_dbi($dbtype, @args);
  } elsif (my $sub = $schema->can("connect_to_$dbtype")) {
    $schema->{dbtype} = $dbtype;
    $sub->($schema, @args);
  } else {
    croak sprintf("%s: Unknown dbtype: %s", MY, $dbtype);
  }
}

sub connect_to_sqlite {
  (my MY $schema, my ($sqlite_fn, %opts)) = @_;
  # XXX: Adapt begin immediate transaction, for SQLITE_BUSY
  my $ro = delete($opts{RO}) // 0;
  my $dbi_dsn = "dbi:SQLite:dbname=$sqlite_fn";
  my $first_time = not -e $sqlite_fn;
  $schema->{dbtype} //= 'sqlite';
  $schema->configure(%opts) if %opts;
  $schema->{cf_auto_create} //= 1;
  $schema->connect_to_dbi($dbi_dsn, undef, undef, AutoCommit => $ro);
  $schema->dbinit_sqlite($sqlite_fn) if $first_time;
  $schema;
}

sub connect_to_dbi {
  (my MY $schema, my ($dbi_dsn, $user, $auth, %opts)) = @_;
  my %attr;
  foreach ([RaiseError => 1], [PrintError => 0], [AutoCommit => 0]) {
    $attr{$$_[0]} = delete($opts{$$_[0]}) // $$_[1];
  }
  $schema->configure(%opts) if %opts;
  require DBI;
  my $dbh = $schema->{cf_DBH} = DBI->connect($dbi_dsn, $user, $auth, \%attr);
  $schema->after_connect;
  $schema;
}

#
# ./lib/MyApp.pm create sqlite data/myapp.db3
#
sub create {
  (my MY $schema, my @spec) = @_;
  my $dbh = $schema->dbh(@spec ? \@spec : ());
  $schema->ensure_created_on($dbh);
  $schema;
}

sub ensure_created_on {
  (my MY $schema, my $dbh) = @_;
  my $nchanges;
  foreach my Table $table (@{$schema->{table_list}}) {
    next if $schema->has_table($table->{cf_name}, $dbh);
    foreach my $create ($schema->sql_create_table($table)) {
      unless ($schema->{cf_verbose}) {
      } elsif ($schema->{cf_verbose} >= 2) {
	print STDERR "-- $table->{cf_name} --\n$create\n\n"
      } elsif ($schema->{cf_verbose} and $create =~ /^create table /i) {
	print STDERR "CREATE TABLE $table->{cf_name}\n";
      }
      $dbh->do($create);
      $nchanges++;
    }
  }
  $dbh->commit if $nchanges and not $dbh->{AutoCommit};
}

sub has_table {
  (my MY $schema, my ($table, $dbh)) = @_;
  if ($$schema{dbtype}
      and my $sub = $schema->can("has_table_$$schema{dbtype}")) {
    $sub->($schema, $table, $dbh);
  } else {
    $dbh ||= $schema->dbh;
    $dbh->tables("", "", $table, 'TABLE');
  }
}

sub has_table_sqlite {
  (my MY $schema, my ($table, $dbh)) = @_;
  my ($name) = $dbh->selectrow_array(<<'END', undef, $table) or return undef;
select name from sqlite_master where type = 'table' and name = ?
END
  $name;
}

sub tables {
  my MY $schema = shift;
  keys %{$schema->{table_dict}};
}

sub has_column {
  (my MY $schema, my ($table, $column, $dbh)) = @_;
  my $hash = $schema->columns_hash($table, $dbh || $schema->dbh);
  exists $hash->{$column};
}

sub columns_hash {
  (my MY $schema, my ($table, $dbh)) = @_;
  $dbh ||= $schema->dbh;
  my $sth = $dbh->prepare("select * from $table limit 0");
  $sth->execute;
  my %hash = %{$sth->{NAME_hash}};
  \%hash;
}

sub drop {
  (my MY $schema) = @_;
  foreach my $sql ($schema->sql_drop) {
    $schema->dbh->do($sql);
  }
}

#========================================

sub list_items {
  (my MY $self, my $opts, my $itemlist) = @_;
  if ($opts->{raw}) {
    @$itemlist
  } else {
    map {(my Item $item = $_)->{cf_name}} @$itemlist
  }
}

sub list_tables {
  (my MY $self, my %opts) = @_;
  $self->list_items(\%opts, $self->{table_list});
}

sub list_relations {
  (my MY $self, my ($tabName, %opts)) = @_;
  my Table $tab = $self->{table_dict}{$tabName}
    or return;
  if ($opts{raw}) {
    @{$tab->{relationSpec}}
  } else {
    map {
      (my ($relType, $relName, $fkName), my Table $subTab) = @$_;
      $fkName //= do {
	if (my Column $pk = $self->info_table_pk($subTab)
	    || $self->info_table_pk($tab)) {
	  $pk->{cf_name};
	}
      };
      [$relType, $relName, $fkName, $subTab->{cf_name}];
    } @{$tab->{relationSpec}};
  }
}

sub list_table_columns {
  (my MY $self, my ($tabName, %opts)) = @_;
  my Table $tab = $self->{table_dict}{$tabName}
    or return;
  $self->list_items(\%opts, $tab->{col_list});
}

sub info_table {
  (my MY $self, my $name) = @_;
  $self->{table_dict}{$name} //= do {
    push @{$self->{table_list}}
      , my Table $tab = $self->Table->new(name => $name);
    $tab->{not_configured} = 1;
    $tab;
  };
}

sub info_table_pk {
  (my MY $self, my ($tabName, %opts)) = @_;
  my Table $tab = ref $tabName ? $tabName : $self->{table_dict}{$tabName};
  my $pkinfo = $tab->{pk};
  return unless $pkinfo;
  if (wantarray) {
    $self->list_items(\%opts, ref $pkinfo eq 'ARRAY' ? $pkinfo : [$pkinfo]);
  } else {
    ref $pkinfo eq 'ARRAY' ? $pkinfo->[0] : $pkinfo
  }
}

sub get_table {
  my MY $self = shift;
  my ($name, $opts, @colpairs) = @_;
  my Table $tab = $self->info_table($name);
  return $tab if @_ == 1;
  if ($tab and not $tab->{not_configured}) {
    croak "Duplicate definition of table $name";
  }
  $tab->{not_configured} = 0;
  $tab->configure(lhexpand($opts)) if $opts;
  while (@colpairs) {
    # colName => [colSpec]
    # [check => args]
    unless (ref $colpairs[0]) {
      my ($col, $desc) = splice @colpairs, 0, 2;
      $self->add_table_column($tab, $col, ref $desc ? @$desc : $desc);
    } else {
      my ($method, @args) = @{shift @colpairs};
      $method =~ s/^-//;
      # XXX: [has_many => @tables]
      if (my ($relType, @relSpec) = $self->known_rels($method)) {
	$self->add_table_relation($tab, undef, $relType => \@relSpec, @args);
      } else {
	my $sub = $self->can("add_table_\L$method")
	  or croak "Unknown table option '$method' for table $name";
	$sub->($self, $tab, @args);
      }
    }
  }

  $tab;
}

sub add_table_primary_key {
  (my MY $self, my Table $tab, my @args) = @_;
  if ($tab->{pk} and @args) {
    croak "Duplicate PK definition. old $tab->{pk}";
  }
  $tab->{pk} = [map {$tab->{col_dict}{$_}} @args];
}

sub add_table_unique {
  (my MY $self, my Table $tab, my @cols) = @_;
  # XXX: 重複検査
  push @{$tab->{chk_unique}}, [@cols];
}

# -opt は引数無フラグ、又は [-opt, ...] として可変長オプションに使う
sub add_table_relation {
  (my MY $self, my Table $tab, my Column $fkCol
   , my ($relType, $relSpec, $item, $fkName, $atts)) = @_;
  unless (defined $item) {
    croak "Undefined relation spec for table $tab->{cf_name}";
  }
  my Table $subTab = ref $item ? $self->get_table(@$item)
    : $self->info_table($item);
  my $relName = $relSpec->[0] // lc($subTab->{cf_name});
  $fkName //= $relSpec->[1] // $fkCol->{cf_name}
    // $subTab->{reference_dict}{$tab->{cf_name}};
  push @{$tab->{relationSpec}}
    , [$relType => $relName, $fkName, $subTab];
}

sub add_table_column {
  (my MY $self, my Table $tab, my ($colName, $type, @colSpec)) = @_;
  if ($tab->{col_dict}{$colName}) {
    croak "Conflicting column name $colName for table $tab->{cf_name}";
  }
  # $tab.$colName is encoded by $refTab.pk
  if (ref $type) {
    croak "Deprecated column spec in $tab->{cf_name}.$colName";
  }
  Carp::cluck "Column type $tab->{cf_name}.$colName is undef"
      unless defined $type;

  my (@opt, @rels);
  while (@colSpec) {
    unless (defined (my $key = shift @colSpec)) {
      croak "Undefined colum spec for $tab->{cf_name}.$colName";
    } elsif (ref $key) {
      my ($method, @args) = @$key;
      $method =~ s/^-//;
      # XXX: [has_many => @tables]
      # XXX: [unique => k1, k2..]
      if (my ($relType, @relSpec) = $self->known_rels($method)) {
	push @rels, [$relType => \@relSpec, @args];
      } else {
	croak "Unknown method $method";
      }
    } elsif ($key =~ /^-/) {
      push @opt, $key => 1;
    } elsif (my ($relType, @relSpec) = $self->known_rels($key)) {
      push @rels, [$relType, \@relSpec, shift @colSpec]
    } else {
      push @opt, $key, shift @colSpec;
    }
  }
  push @{$tab->{col_list}}, ($tab->{col_dict}{$colName})
    = (my Column $col) = $self->Column->new
      (@opt, name => $colName, type => $type);
  $tab->{pk} = $col if $col->{cf_primary_key};

  $self->add_table_relation($tab, $col, @$_) for @rels;

  # XXX: Validation: name/option conflicts and others.
  $col;
}

sub verify_schema {
  (my MY $self) = @_;
  my @not_configured;
  foreach my Table $tab (lexpand($self->{table_list})) {
    if ($tab->{not_configured}) {
      push @not_configured, $tab->{cf_name};
      next;
    }
    # foreach my Column $col (lexpand($tab->{col_list})) { }
  }
  if (@not_configured) {
    croak "Some tables are not configure, possibly spellmiss!: @not_configured";
  }
}

{
  my %known_rels = qw(has_many 1 has_one 1 belongs_to 1
		      many_to_many 1 might_have 1
		    );
  sub known_rels {
    (my MY $self, my $desc) = @_;
    my ($relType, $relName, $fkName) = split /:/, $desc, 3;
    return unless $known_rels{$relType};
    ($relType, $relName, $fkName)
  }
}

#========================================

sub sql_create {
  (my MY $schema, my %opts) = @_;
  $schema->foreach_tables_do('sql_create_table', \%opts)
}

sub default_dbtype {'sqlite'}
sub sql_create_table {
  (my MY $schema, my Table $tab, my $opts) = @_;
  my (@cols, @indices);
  my $dbtype = $opts->{dbtype} || $schema->default_dbtype;
  my $sub = $schema->can($dbtype.'_sql_create_column')
    || $schema->can('sql_create_column');
  foreach my Column $col (@{$tab->{col_list}}) {
    push @cols, $sub->($schema, $tab, $col, $opts);
    push @indices, $col if $col->{cf_indexed};
  }
  foreach my $constraint (map {$_ ? @$_ : ()} $tab->{chk_unique}) {
    push @cols, sprintf q{unique(%s)}, join(", ", @$constraint);
  }

  # XXX: SQLite specific.
  push my @create
    , sprintf qq{CREATE TABLE %s\n(%s)}, $tab->{cf_name}
      , join "\n, ", @cols;

  foreach my Column $ix (@indices) {
    push @create
      , sprintf q{CREATE INDEX %1$s_%2$s on %1$s(%2$s)}
	, $tab->{cf_name}, $ix->{cf_name};
  }

  wantarray ? @create : join(";\n", @create);
}

# XXX: text => varchar(80)
sub map_coltype {
  (my MY $schema, my $typeName) = @_;
  $schema->{cf_coltype_map}{$typeName} // $typeName;
}

sub sql_create_column {
  (my MY $schema, my Table $tab, my Column $col, my $opts) = @_;
  join(" ", $col->{cf_name}
       , $schema->map_coltype($col->{cf_type})
       , ($col->{cf_primary_key} ? "primary key" : ())
       , ($col->{cf_unique} ? "unique" : ())
       , ($col->{cf_autoincrement} ? "autoincrement" : ()));
}

sub sqlite_sql_create_column {
  (my MY $schema, my Table $tab, my Column $col, my $opts) = @_;
  unless (defined $col->{cf_type}) {
    croak "Column type is not yet defined! $tab->{cf_name}.$col->{cf_name}"
  } elsif ($col->{cf_type} =~ /^int/i && $col->{cf_primary_key}) {
    "$col->{cf_name} integer primary key"
  } else {
    $schema->sql_create_column($tab, $col, $opts);
  }
}

sub sql_drop {
  shift->foreach_tables_do
    (sub {
       (my Table $tab) = @_;
       qq{drop table $tab->{cf_name}};
     })
}

sub foreach_tables_do {
  (my MY $self, my $method, my $opts) = @_;
  my $code = ref $method ? $method : sub {
    $self->$method(@_);
  };
  my @result;
  my $wantarray = wantarray;
  foreach my Table $tab (@{$self->{table_list}}) {
    push @result, map {
      $wantarray ? $_ . "\n" : $_
    } $code->($tab, $opts);
   }
  wantarray ? @result : join(";\n", @result);
}

########################################
sub to_encode {
  (my MY $self, my $tabName, my $keyCol, my @otherCols) = @_;

  my $to_find = $self->to_find($tabName, $keyCol);
  my $to_ins = $self->to_insert($tabName, $keyCol, @otherCols);

  sub {
    my ($value, @rest) = @_;
    $to_find->($value) || $to_ins->($value, @rest);
  };
}

# to_fetchall は別途用意する
sub to_find {
  (my MY $self, my ($tabName, $keyCol, $rowidCol)) = @_;
  my $sql = $self->sql_to_find($tabName, $keyCol, $rowidCol);
  print STDERR "-- $sql\n" if $self->{cf_verbose};
  my $sth;
  sub {
    my ($value) = @_;
    $sth ||= $self->dbh->prepare($sql);
    $sth->execute($value);
    my ($rowid) = $sth->fetchrow_array
      or return;
    $rowid;
  };
}

sub to_fetch {
  (my MY $self, my ($tabName, $keyColList, $resColList, @rest)) = @_;
  my $sql = $self->sql_to_fetch($tabName, $keyColList, $resColList, @rest);
  print STDERR "-- $sql\n" if $self->{cf_verbose};
  my $sth;
  sub {
    my (@value) = @_;
    $sth ||= $self->dbh->prepare($sql);
    $sth->execute(@value);
    $sth;
  };
}

sub to_insert {
  (my MY $self, my ($tabName, @fields)) = @_;
  my $sql = $self->sql_to_insert($tabName, @fields);
  print STDERR "-- $sql\n" if $self->{cf_verbose};
  my $sth;
  sub {
    my (@value) = @_;
    $sth ||= $self->dbh->prepare($sql);
    # print STDERR "-- inserting @value to $sql\n";
    $sth->execute(@value);
    $self->dbh->last_insert_id('', '', '', '');
  };
}

sub sql_to_find {
  (my MY $self, my ($tabName, $keyCol, $rowidCol)) = @_;
  my Table $tab = $self->{table_dict}{$tabName}
    or croak "No such table: $tabName";
  # XXX: col name check.
  $rowidCol ||= $self->rowid_col($tab);
  <<END;
select $rowidCol from $tabName where $keyCol = ?
END
}

sub sql_to_fetch {
  (my MY $self, my ($tabName, $keyColList, $resColList, %opts)) = @_;
  my $group_by = delete $opts{group_by};
  my $order_by = delete $opts{order_by};
  my Table $tab = $self->{table_dict}{$tabName}
    or croak "No such table: $tabName";
  # XXX: col name check... いや、式かもしれないし。
  my $cols = $resColList ? join(", ", lexpand $resColList) : '*';
  my $where = do {
    unless (defined $keyColList) {
      undef;
    } elsif (not ref $keyColList) {
      "$keyColList = ?"
    } elsif (ref $keyColList eq 'ARRAY') {
      join " AND ", map {"$_ = ?"} @$keyColList
    } elsif (ref $keyColList eq 'SCALAR') {
      # RAW SQL
      $$keyColList;
    } else {
      die "Not yet implemented!";
    }
  };
  if ($group_by) {
    $where .= " GROUP BY $group_by";
  }
  if ($order_by) {
    $where .= " ORDER BY $order_by";
  }
  qq|select $cols from $tabName| . (defined $where ? " where $where" : "");
}


sub sql_to_insert {
  (my MY $self, my ($tabName, @fields)) = @_;
  sprintf qq{insert into $tabName(%s) values(%s)}
    , join(", ", @fields)
      , join(", ", map {'?'} @fields);
}

sub default_rowid_col { 'rowid' }
sub rowid_col {
  (my MY $schema, my Table $tab) = @_;
  if (my Column $pk = $tab->{pk}) {
    $pk->{cf_name}
  } else {
    $schema->default_rowid_col;
  }
}

########################################

sub add_inc {
  my ($pack, $callpack) = @_;
  $callpack =~ s{::}{/}g;
  $INC{$callpack . '.pm'} = 1;
}

########################################

sub run {
  my $pack = shift;
  $pack->cmd_help unless @_;
  my MY $obj = $pack->new(MY->parse_opts(\@_));
  my $cmd = shift || "help";
  $obj->configure(MY->parse_opts(\@_));
  my $method = "cmd_$cmd";
  if (my $sub = $obj->can("cmd_$cmd")) {
    $sub->($obj, @_);
  } elsif ($sub = $obj->can($cmd)) {
    my @res = $sub->($obj, @_);
    exit 1 unless @res;
    unless (@res == 1 and defined $res[0] and $res[0] eq "1") {
      if (grep {defined $_ && ref $_} @res) {
	require Data::Dumper;
	print Data::Dumper->new([$_])->Indent(0)->Terse(1)->Dump
	  , "\n" for @res;
      } else {
	print join("\n", @res), "\n";
      }
    }
  } else {
    croak "No such method $cmd for $pack\n";
  }
  $obj->DESTROY; # To make sure committed.
}

sub cmd_help {
  my ($self) = @_;
  my $pack = ref($self) || $self;
  my $stash = do {
    my $pkg = $pack . '::';
    no strict 'refs';
    \%{$pkg};
  };
  my @methods = sort grep s/^cmd_//, keys %$stash;
  croak "Usage: @{[basename($0)]} method args..\n  "
    . join("\n  ", @methods) . "\n";
}

#========================================

sub ymd_hms {
  my ($pack, $time, $as_utc) = @_;
  my ($S, $M, $H, $d, $m, $y) = map {
    $as_utc ? gmtime($_) : localtime($_)
  } $time;
  sprintf q{%04d-%02d-%02d %02d:%02d:%02d}, 1900+$y, $m+1, $d, $H, $M, $S;
}

sub lhexpand {
  return unless defined $_[0];
  ref $_[0] eq 'HASH' ? %{$_[0]}
    : ref $_[0] eq 'ARRAY' ? @{$_[0]}
      : croak "Invalid option: $_[0]";
}

1;
