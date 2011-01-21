package YATT::Lite::DBSchema::DBIC; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use Carp;

use base qw(YATT::Lite::DBSchema);
use fields qw(DBIC DBIC_package);

require DBIx::Class::Core;

sub DBIC_SCHEMA {'YATT::Lite::DBSchema::DBIC::DBIC_SCHEMA'}

use YATT::Lite::Types
  ([Table => -fields => [qw(cf_package cf_components)]]
   , [Column => -fields => [qw(cf_dbic_opts)]]
  );

use YATT::Lite::Util qw(globref lexpand);

sub import {
  my ($pack) = shift;
  return unless @_;
  $pack->buildns(@_);
}

# use YATT::Lite::DBSchema::DBIC $pkg => @desc;
#
# $pkg                 ISA DBIC_SCHEMA (ISA DBIx::Class::Schema)
# ${pkg}::Result::$tab ISA DBIx::Class::Core

sub buildns {
  my ($myPkg, $DBIC) = splice @_, 0, 2;
  my MY $schema = $myPkg->new(@_);

  # DBIC->YATT_DBSchema holds YATT::Lite::DBSchema::DBIC instance.
  *{globref($DBIC, 'YATT_DBSchema')} = sub {
    my $dbic = shift;
    # Class method として呼んだときは, schema に set しない。
    $schema->{DBIC} ||= $dbic if defined $dbic and ref $dbic; # XXX: weaken??
    $schema;
  };
  $schema->{DBIC_package} = $DBIC;

  *{globref($DBIC, 'ISA')} = [$myPkg->DBIC_SCHEMA];
  $myPkg->add_inc($DBIC);

  foreach my Table $tab (@{$schema->{table_list}}) {
    # XXX: 正確には rowClass よね、これって。
    # XXX: じゃぁ ResultSet の方は作らなくてよいのか?
    my $tabClass = $tab->{cf_package}
      = join('::', $DBIC, Result => $tab->{cf_name});
    *{globref($tabClass, 'ISA')} = ['DBIx::Class::Core'];
    $myPkg->add_inc($tabClass);

    my Column $pk = $schema->info_table_pk($tab);
    my @comp = (qw/Core/, lexpand($tab->{cf_components}));
    push @comp, qw(PK::Auto) if $pk and $pk->{cf_autoincrement};

    $tabClass->load_components(@comp);
    $tabClass->table($tab->{cf_name});
    {
      my @colSpecs;
      foreach my Column $col (@{$tab->{col_list}}) {
	# dbic_opts;
	my %dbic_opts = (data_type => $col->{cf_type}
			 , map(defined $_ ? %$_ : (), $col->{cf_dbic_opts}));
	push @colSpecs, $col->{cf_name} => \%dbic_opts;
      }
      $tabClass->add_columns(@colSpecs);
    }
    $tabClass->set_primary_key($schema->info_table_pk($tab)) if $pk;
  }
  # Relationship の設定と、 register_class の呼び出し。
  foreach my Table $tab (@{$schema->{table_list}}) {
    my $tabClass = $tab->{cf_package};
    foreach my $rel ($schema->list_relations($tab->{cf_name})) {
      my ($relType, @relOpts) = @$rel;
      if (my $sub = $myPkg->can("add_relation_$relType")) {
	$sub->($myPkg, $schema, $tab, @relOpts);
	next;
      }

      my ($relName, $fkName, $fTabName) = @relOpts;
      unless (defined $fTabName) {
	croak "Foreign table is empty for $tab->{cf_name} $relType $relName $fkName";
      }
      my $fTab = $schema->{table_dict}{$fTabName};
      # table の package 名が確定するまで、relation の設定を遅延させたいから。
      print STDERR <<END if $schema->{cf_verbose};
-- $tabClass->$relType($relName, $fTab->{cf_package}, @{[
defined $fkName ? $fkName : 'undef']})
END
      eval {
	$tabClass->$relType($relName, $fTab->{cf_package}, $fkName);
      };
      if ($@) {
	die "Relationship Error in: $relType $relName, foreign="
	  .$fTab->{cf_package}.": $@";
      }
    }
    # register_class は Relationship 設定が済んでからじゃないとダメ?
    $DBIC->register_class($tab->{cf_name}, $tabClass);
  }

  $schema;
}

# XXX: 上と被っているので、まとめるべし。
sub add_relation_many_to_many {
  (my $myPkg, my MY $schema, my Table $tab
   , my ($relName, $fkName, $tabName)) = @_;
  my $relType = 'many_to_many';
  my $tabClass = $tab->{cf_package};
  print STDERR <<END if $schema->{cf_verbose};
-- $tabClass->$relType($relName, $tabName, $fkName)
END
  eval {
    $tabClass->$relType($relName, $tabName, $fkName)
  };
  if ($@) {
    die "Relationship Error in: $relType ($relName, $tabName, $fkName)".$@;
  }
}

*deploy = *ensure_created; *deploy = *ensure_created;
sub ensure_created {
  (my MY $self, my $dbic) = @_;
  $dbic ||= $self->{DBIC};
  $dbic->storage->dbh_do
    (sub {
       (my ($storage, $dbh), my MY $self) = @_;
       $self->ensure_created_on($dbh);
     }, $self)
}

# XXX: delegate は、やりすぎだったかもしれない。
sub add_delegate {
  my ($pack, $name) = @_;
  *{globref($pack, $name)} = sub {
    my MY $self = shift;
    $self->{DBIC}->$name(@_);
  };
}

foreach my $name (keys %DBIx::Class::Schema::) {
  next unless $name =~ /^[a-z]\w*$/;
  next unless *{$DBIx::Class::Schema::{$name}}{CODE};
  next if $YATT::Lite::DBSchema::DBIC::{$name};
  MY->add_delegate($name);
}

{
  package YATT::Lite::DBSchema::DBIC::DBIC_SCHEMA;
  use base qw(DBIx::Class::Schema);
  use Carp;
  # XXX: Should this hold (weakened) ref to DBSchema?

  # Aid to migrate from YATT_DBSchema->to_zzz methods.
  sub to_find {
    my ($dbic, $tabName, $keyCol, $rowidCol) = @_;
    my $rs = $dbic->resultset($tabName);
    unless (defined $keyCol) {
      sub { $rs->find(@_) }
    } elsif (not defined $rowidCol) {
      sub {
	my ($value) = @_;
	my $row = $rs->find({$keyCol => $value})
	  or return undef;
	$row->id;
      };
    } else {
      sub {
	my ($value) = @_;
	my $row = $rs->find({$keyCol => $value})
	  or return undef;
	$row->get_column($rowidCol);
      };
    }
  }

  sub to_insert {
    my ($dbic, $tabName, @fields) = @_;
    my $rs = $dbic->resultset($tabName);
    unless (my ($pkCol, @morePkCol) = $rs->result_source->primary_columns) {
      # If primary key is not defined, row obj is returned.
      $dbic->to_insert_obj($tabName, @fields);
    } elsif (@morePkCol) {
      croak "table '$tabName' has multiple pk col, use to_insert_obj() please!";
    } else {
      sub {
	my %rec;
	@rec{@fields} = @_;
	my $row = $rs->new(\%rec)->insert;
	$row->get_column($pkCol);
      }
    }
  }

  # This returns row object, not primary key.
  sub to_insert_obj {
    my ($dbic, $tabName, @fields) = @_;
    my $rs = $dbic->resultset($tabName);
    sub {
      my %rec;
      @rec{@fields} = @_;
      $rs->new(\%rec)->insert;
    };
  }

  sub to_encode {
    my ($dbic, $tabName, $keyCol, @otherCols) = @_;
    my $to_find = $dbic->to_find($tabName, $keyCol);
    my $to_ins = $dbic->to_insert($tabName, $keyCol, @otherCols);

    sub {
      my ($value, @rest) = @_;
      $to_find->($value) || $to_ins->($value, @rest);
    };
  }

  sub to_fetch {
    my ($dbic, $tabName, $keyColList, $resColList, @rest) = @_;
    my $sql = $dbic->YATT_DBSchema
      ->sql_to_fetch($tabName, $keyColList, $resColList, @rest);
    my $storage = $dbic->storage;
    # XXX: dbh_do
    my $sth;
    sub {
      my (@value) = @_;
      $sth ||= $storage->dbh->prepare($sql);
      $sth->execute(@value);
      $sth;
    }
  }
}

1;
