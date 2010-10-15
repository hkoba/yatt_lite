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

	       cf_after_dbinit
	       cf_group_writable
	     ));

use YATT::Lite::Types
  ([Item => -fields => [qw(cf_name)]
   , [Table => -fields => [qw(pk chk_unique
			      chk_index chk_check colNames
			      relationSpec
			      Column)]]
   , [Column => -fields => [qw(cf_type
			       cf_hidden
			       cf_unique
			       cf_indexed
			       cf_primary_key
			       cf_autoincrement
			     )]]]);

use YATT::Lite::Util qw(coalesce globref ckeval);

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
      $self->add_table(@$item);
    } else {
      croak "Invalid schema item: $item";
    }
  }
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
  (my MY $schema, my ($dbtype)) = splice @_, 0, 2;
  if (my $sub = $schema->can("connect_to_$dbtype")) {
    $schema->{dbtype} = $dbtype;
    $sub->($schema, @_);
  } else {
    croak sprintf("%s: Unknown dbtype: %s", MY, $dbtype);
  }
}

sub connect_to_sqlite {
  (my MY $schema, my ($dbname, $rwflag)) = @_;
  my $ro = defined $rwflag && $rwflag =~ /ro/i;
  my $dbi_dsn = "dbi:SQLite:dbname=$dbname";
  $schema->{cf_auto_create} = 1;
  $schema->connect_to_dbi
    ($dbi_dsn, undef, undef
     , RaiseError => 1, PrintError => 0, AutoCommit => $ro);
}

sub connect_to_dbi {
  (my MY $schema, my ($dbi_dsn, $user, $auth, %param)) = @_;
  map {$param{$$_[0]} = $$_[1] unless defined $param{$$_[0]}}
    ([RaiseError => 1], [PrintError => 0], [AutoCommit => 0]);
  require DBI;
  if ($dbi_dsn =~ m{^dbi:(\w+):}) {
    $schema->configure(dbtype => lc($1));
  }
  my $dbh = $schema->{cf_DBH} = DBI->connect($dbi_dsn, $user, $auth, \%param);
  $schema->create if $schema->{cf_auto_create};
  $dbh;
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
  foreach my Table $table (@{$schema->{table_list}}) {
    next if $schema->has_table($table->{cf_name}, $dbh);
    foreach my $create ($schema->sql_create_table($table)) {
      print STDERR "-- $table->{cf_name} --\n$create\n\n"
	if $schema->{cf_verbose};
      $dbh->do($create);
    }
  }
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

sub add_table {
  (my MY $self, my ($name, $opts, @colpairs)) = @_;
  $self->{table_dict}{$name} ||= do {
    push @{$self->{table_list}}
      , my Table $tab = $self->Table->new(name => $name);
    if (ref $opts eq 'ARRAY') {
      push @{$tab->{relationSpec}}, @$opts;
    } else {
      # XXX HASH option だったら？
    }
    while (@colpairs) {
      # colName => [colSpec]
      # [check => args]
      unless (ref $colpairs[0]) {
	my ($col, $desc) = splice @colpairs, 0, 2;
	if (defined $col) {
	  $self->add_table_column($tab, $col, ref $desc ? @$desc : $desc);
	} else {
	  # XXX: column 一つに絞れない relationship の宣言。
	}
      } else {
	my $spec = shift @colpairs;
	# XXX: [unique => k1, k2..]
      }
    }
    $tab;
  };
}

sub hyphen2bool {
  map {/^-(\w+)$/ ? ($1 => 1) : $_} @_;
}

sub add_table_column {
  (my MY $self, my Table $tab, my ($colName, $type)) = splice @_, 0, 4;
  if ($tab->{colNames}{$colName}) {
    croak "Conflicting column name $colName for table $tab->{cf_name}";
  }
  my ($colPkg, @opt, @rels) = $self->Column;
  while (@_) {
    if ((my $key = shift) =~ /^-/) {
      push @opt, $key => 1;
    } elsif (my ($relType, $relName, $fkName) = $self->known_rels($key)) {
      push @rels, [$relType, $relName, $fkName, shift]
    } else {
      push @opt, $key, shift;
    }
  }
  push @{$tab->{Column}}, ($tab->{colNames}{$colName})
    = (my Column $col) = $colPkg->new(@opt, name => $colName, type => $type);

  $tab->{pk} = $col if $col->{cf_primary_key};

  foreach my $rels (@rels) {
    my ($relType, $relName, $fkName, $relSpec) = @$rels;
    my Table $subTab = do {
      if (ref $relSpec) {
	$self->add_table(@$relSpec);
      } else {
	$self->{table_dict}{$relSpec} || die "Unknown table $relSpec!";
      }
    };
    push @{$tab->{relationSpec}}
      , [$relType, $relName || $subTab->{cf_name}, $fkName, $subTab];
    # XXX: belongs_to の自動設定は？
    if (my $sub = $self->can("backrel_of_$relType")) {
      $sub->($self, $tab, $col, $subTab)
    }
  }
  # XXX: Validation: name/option conflicts and others.
  $col;
}

sub backrel_of_has_many {shift->backrel_of_own(@_)}
sub backrel_of_has_one {shift->backrel_of_own(@_)}

sub backrel_of_own {
  (my MY $self, my Table $owner, my Column $col, my Table $subTab) = @_;
  push @{$subTab->{relationSpec}}
    , [belongs_to => $owner->{cf_name}, $col->{cf_name}, $owner];
}

{
  my %known_rels = qw(has_many 1 has_one 1 belongs_to 1);
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
  foreach my Column $col (@{$tab->{Column}}) {
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
}

sub sql_create_column {
  (my MY $schema, my Table $tab, my Column $col, my $opts) = @_;
  join(" ", $col->{cf_name}
       , $col->{cf_type}
       , ($col->{cf_primary_key} ? "primary key" : ())
       , ($col->{cf_unique} ? "unique" : ())
       , ($col->{cf_autoincrement} ? "autoincrement" : ()));
}

sub sqlite_sql_create_column {
  (my MY $schema, my Table $tab, my Column $col, my $opts) = @_;
  if ($col->{cf_type} =~ /^int/i && $col->{cf_primary_key}) {
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

sub connect_dbi {
  my MY $self = shift;
  require DBI;
  $self->{cf_DBH} = DBI->connect(@_);
  $self->after_connect;
  $self;
}

sub after_connect {
  my MY $self = shift;
  if ($self->{cf_auto_create} // 1) {
    $self->ensure_created_on($self->{cf_DBH});
  }
}

sub connect_sqlite {
  my MY $self = shift;
  my ($sqlite_fn, %opts) = @_;
  $self->{dbtype} = 'sqlite';
  my $first_time = not -e $sqlite_fn;
  $self->connect_dbi
    ("dbi:SQLite:dbname=$sqlite_fn", undef, undef
     , {PrintError => 0, RaiseError => 1, AutoCommit => 1});

  $self->dbinit_sqlite($sqlite_fn) if $first_time;
  # XXX: $opts{RO} か否かで transaction の種類を
  $self;
}

sub dbinit_sqlite {
  (my MY $self, my $sqlite_fn) = @_;
  chmod 0664, $sqlite_fn if $self->{cf_group_writable} // 1;
  if (my $hook = $self->{cf_after_dbinit}) {
    if (ref $hook eq 'CODE') {
      $hook->($self, $sqlite_fn);
    } else {
      $hook->after_dbinit;
    }
  }
}

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
    die "No such method $cmd for $pack\n";
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
  die "Usage: @{[basename($0)]} method args..\n  "
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

1;
