package YATT::Lite::Types;
use strict;
use warnings FATAL => qw(all);
use parent qw(YATT::Lite::Object);
use Carp;
require YATT::Lite::Inc;

sub Desc () {'YATT::Lite::Types::TypeDesc'}
{
  package YATT::Lite::Types::TypeDesc; sub Desc () {__PACKAGE__}
  use parent qw(YATT::Lite::Object);
  BEGIN {
    our %FIELDS = map {$_ => 1}
      qw/cf_name cf_ns cf_fields cf_overloads cf_alias cf_base cf_eval
	 fullname
	 cf_constants cf_export_default/
  }
  sub pkg {
    my Desc $self = shift;
    join '::', $self->{cf_ns}, $self->{cf_name};
  }
}

use YATT::Lite::Util qw(globref look_for_globref lexpand ckeval);

sub import {
  my $pack = shift;
  my $callpack = caller;
  $pack->buildns($callpack, @_)
}

sub create {
  my $pack = shift;
  my $callpack = shift;
  my Desc $root = $pack->Desc->new(ns => $callpack);
  while (@_ >= 2 and not ref $_[0]) {
    $root->configure(splice @_, 0, 2);
  }
  wantarray ? ($root, $pack->parse_desc($root, @_)) : $root;
}

sub buildns {
  (my Desc $root, my @desc) = shift->create(@_);
  my $debug = $ENV{DEBUG_YATT_TYPES};
  my (@script, @task);
  my $export_ok = do {
    my $sym = globref($$root{cf_ns}, 'EXPORT_OK');
    *{$sym}{ARRAY} // (*$sym = []);
  };
  if (my $sub = $$root{cf_ns}->can('export_ok')) {
    push @$export_ok, $sub->($$root{cf_ns});
  }
  {
    my $sym = globref($$root{cf_ns}, 'export_ok');
    *$sym = sub { @$export_ok } unless *{$sym}{CODE};
  }
  foreach my Desc $obj (@desc) {
    push @$export_ok, $obj->{cf_name};
    $obj->{fullname} = join '::', $$root{cf_ns}, $obj->{cf_name};
    push @script, qq|package $obj->{fullname};|;
    push @script, q|use YATT::Lite::Inc;|;
    my $base = $obj->{cf_base} || $root->{cf_base}
      || safe_invoke($$root{cf_ns}, $obj->{cf_name})
	|| 'YATT::Lite::Object';
    push @script, sprintf q|use base qw(%s);|, $base;
    push @script, sprintf q|use fields qw(%s);|, join " ", @{$obj->{cf_fields}}
      if $obj->{cf_fields};
    push @script, sprintf q|use overload qw(%s);|
      , join " ", @{$obj->{cf_overloads}} if $obj->{cf_overloads};
    push @script, $obj->{cf_eval} if $obj->{cf_eval};
    push @script, "\n";

    push @task, [\&add_alias, $$root{cf_ns}, $obj->{cf_name}, $obj->{cf_name}];
    foreach my $alias (lexpand($obj->{cf_alias})) {
      push @task, [\&add_alias, $$root{cf_ns}, $alias, $obj->{cf_name}];
      push @$export_ok, $alias;
    }
    foreach my $spec (lexpand($obj->{cf_constants})) {
      push @task, [\&add_const, $obj->{fullname}, @$spec];
    }
  }
  my $script = join(" ", @script, "; 1");
  print $script, "\n" if $debug;
  ckeval($script);
  foreach my $task (@task) {
    my ($sub, @args) = @$task;
    $sub->(@args);
  }
  if ($root->{cf_export_default}) {
    my $export = do {
      my $sym = globref($$root{cf_ns}, 'EXPORT');
      *{$sym}{ARRAY} // (*$sym = []);
    };
    @$export = @$export_ok;
  }
  foreach my Desc $obj (@desc) {
    my $sym = look_for_globref($obj->{fullname}, 'FIELDS');
    if ($sym and my $fields = *{$sym}{HASH}) {
      print "Fields in type $obj->{fullname}: "
	, join(" ", sort keys %$fields), "\n" if $debug;
    } elsif ($obj->{cf_fields}) {
      croak "Failed to define type fields for '$obj->{fullname}': "
	. join(" ", @{$obj->{cf_fields}});
    }
  }
}

sub add_alias {
  my ($pack, $alias, $name) = @_;
  add_const($pack, $alias, join('::', $pack, $name));
}

sub add_const {
  my ($pack, $alias, $const) = @_;
  *{globref($pack, $alias)} = sub () { $const };
}

sub safe_invoke {
  my ($obj, $method) = splice @_, 0, 2;
  my $sub = $obj->can($method)
    or return;
  $sub->($obj, @_);
}

sub parse_desc {
  (my $pack, my Desc $parent) = splice @_, 0, 2;
  my (@desc);
  while (@_) {
    unless (defined (my $item = shift)) {
      croak "Undefined type desc!";
    } elsif (ref $item) {
      my @base = (base => $parent->pkg) if $parent->{cf_name};
      push @desc, my Desc $sub = $pack->Desc->new
	(name => shift @$item, ns => $parent->{cf_ns}, @base);
      push @desc, $pack->parse_desc($sub, @$item);
    } elsif (@_) {
      $item =~ s/^-//;
      $parent->configure($item, shift);
    } else {
      croak "Missing parameter for type desc $item";
    }
  }
  @desc;
}

1;
