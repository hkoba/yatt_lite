package YATT::Lite::DBSchema::DBIC; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);

use base qw(YATT::Lite::DBSchema);
use fields qw(DBIC DBIC_package);

require DBIx::Class::Core;

sub DBIC_SCHEMA {'YATT::Lite::DBSchema::DBIC::DBIC_SCHEMA'}

use YATT::Lite::Types
  ([Table => -fields => [qw(cf_package)]]
   , ['Column'] # To import type aliases.
  );

use YATT::Lite::Util qw(globref);

sub import {
  my ($pack) = shift;
  return unless @_;
  $pack->buildns(@_);
}

# use YATT::Lite::DBSchema::DBIC $pkg => @desc;
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
    my @comp = qw/Core/;
    push @comp, qw(PK::Auto) if $pk and $pk->{cf_autoincrement};

    $tabClass->load_components(@comp);
    $tabClass->table($tab->{cf_name});
    $tabClass->add_columns(map {(my Column $col = $_)->{cf_name}}
			   @{$tab->{col_list}});
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
}

1;
