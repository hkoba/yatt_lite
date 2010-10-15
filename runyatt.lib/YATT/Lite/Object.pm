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
      confess "No such config item $name in class " . ref $self;
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
      confess "No such config item $from in class " . ref $self;
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
      confess "No such config item $from in class " . ref $self;
    }
    defined $self->{"cf_$from"} ? ($to => $self->{"cf_$from"}) : ()
  } @_;
}

# Or, say, with_option.
sub let {
  my MY $self = shift;
  my $callback = pop;
  carp "\n\nUsage: \$obj->let(key => value, ..., sub {})" if @_ % 2;
  my (@keys, @values);
  while (my ($key, $value) = splice @_) {
    push @keys, "cf_$key"; push @values, $value;
  }
  local @{$self}{@keys} = @values;
  $callback->($self);
}

1;
