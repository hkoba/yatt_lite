package YATT::Lite::Object; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use Carp;
use fields;

require YATT::Lite::Util;

sub new {
  my $self = fields::new(shift);
  if (@_) {
    my @task = $self->configure(@_);
    $self->after_new;
    $$_[0]->($self, $$_[1]) for @task;
  } else {
    $self->after_new;
  }
  $self;
}

sub just_new {
  my $self = fields::new(shift);
  # To delay configure_zzz.
  ($self, $self->configure(@_));
}

our $loading_file;
sub _loading_file {
  return "\n  (loaded from unknown file)" unless defined $loading_file;
  sprintf qq|\n  loaded from file '%s'|, $loading_file;
}
sub _with_loading_file {
  my ($self, $fn, $method) = @_[0 .. 2];
  local $loading_file = $fn;
  if (ref $method eq 'CODE') {
    $method->(@_[3 .. $#_]);
  } else {
    $self->$method(@_[3 .. $#_]);
  }
}

# To hide from subclass. (Might harm localization?)
my $NO_SUCH_CONFIG_ITEM = sub {
  my ($self, $name) = @_;
  "No such config item $name in class " . ref($self)
    . $self->_loading_file;
};

sub configure {
  my $self = shift;
  my (@task);
  my $fields = YATT::Lite::Util::fields_hash($self);
  while (my ($name, $value) = splice @_, 0, 2) {
    unless (defined $name) {
      croak "Undefined name given for @{[ref($self)]}->configure(name=>value)!";
    }
    $name =~ s/^-//;
    if (my $sub = $self->can("configure_$name")) {
      push @task, [$sub, $value];
    } elsif (not exists $fields->{"cf_$name"}) {
      confess $NO_SUCH_CONFIG_ITEM->($self, $name);
    } else {
      $self->{"cf_$name"} = $value;
    }
  }
  if (wantarray) {
    # To delay configure_zzz.
    @task;
  } else {
    $$_[0]->($self, $$_[1]) for @task;
    $self;
  }
}

# Hook.
sub after_new {};

#
# util for delegate
#
sub cf_delegate {
  my MY $self = shift;
  my $fields = YATT::Lite::Util::fields_hash($self);
  map {
    my ($from, $to) = ref $_ ? @$_ : ($_, $_);
    unless (exists $fields->{"cf_$from"}) {
      confess $NO_SUCH_CONFIG_ITEM->($self, $from);
    }
    $to => $self->{"cf_$from"}
  } @_;
}

sub cf_delegate_defined {
  my MY $self = shift;
  my $fields = YATT::Lite::Util::fields_hash($self);
  map {
    my ($from, $to) = ref $_ ? @$_ : ($_, $_);
    unless (exists $fields->{"cf_$from"}) {
      confess $NO_SUCH_CONFIG_ITEM->($self, $from);
    }
    defined $self->{"cf_$from"} ? ($to => $self->{"cf_$from"}) : ()
  } @_;
}

# Or, say, with_option.
# XXX: configure_ZZZ hook is not applied.
sub cf_let {
  (my MY $self, my ($binding, $task)) = splice @_, 0, 3;
  my ($keys, $values) = $self->cf_bindings(@$binding);
  local @{$self}{@$keys} = @$values;
  if (ref $task) {
    $task->($self, @_);
  } else {
    $self->$task(@_);
  }
}

sub cf_bindings {
  my MY $self = shift;
  carp "Odd number of key value bindings" if @_ % 2;
  my (@keys, @values);
  while (my ($key, $value) = splice @_, 0, 2) {
    # XXX: key check!
    # XXX: task extraction!
    push @keys, "cf_$key"; push @values, $value;
  }
  (\@keys, \@values);
}

1;
