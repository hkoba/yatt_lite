package YATT::Lite::Connection; sub PROP () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use fields qw(buffer header header_is_printed cookie session
	      cf_header cf_parent_fh cf_handler cf_system cf_db
	      cf_is_error
	      cf_encoding
	      stash
	      debug_stash
	    );
use YATT::Lite::Util qw(globref);
use Carp;

sub prop { my $glob = shift; \%{*$glob}; }
sub build_prop {
  my $class = shift;
  my PROP $prop = fields::new($class);
  while (my ($name, $value) = splice @_, 0, 2) {
    $prop->{"cf_$name"} = $value;
  }
  $prop;
}

sub build_fh_for {
  (my $class, my PROP $prop) = splice @_, 0, 2;
  unless (defined $_[0]) {
    my $enc = $$prop{cf_encoding} ? ":encoding($$prop{cf_encoding})" : '';
    open $_[0], ">$enc", \ ($prop->{buffer} = "") or die $!;
  }
  bless $_[0], $class;
  *{$_[0]} = $prop;
  $_[0];
}

sub new {
  my ($class, $self) = splice @_, 0, 2;
  require IO::Handle;
  $class->build_fh_for($class->build_prop(@_), $self);
  $self->after_new;
  $self;
}

sub after_new {}

sub cf_clone {
  my PROP $prop = prop(my $glob = shift);
  map {
    unless (/^cf_(\w+)/ and defined $prop->{$_}) { () }
    else { ($1 => $prop->{$_}) }
  } keys %$prop;
}

sub buffer {
  my PROP $prop = prop(my $glob = shift);
  $prop->{buffer}
}
sub set_header {
  my PROP $prop = prop(my $glob = shift);
  $prop->{header}{shift()} = shift();
  $glob;
}
sub list_header {
  my PROP $prop = prop(my $glob = shift);
  (map($_ ? %$_ : (), $prop->{header}));
}

sub cget {
  confess "Not enough argument" unless @_ == 2;
  my PROP $prop = prop(my $glob = shift);
  my ($name) = @_;
  $prop->{"cf_$name"};
}

sub configure {
  my PROP $prop = prop(my $glob = shift);
  my $fields = YATT::Lite::Util::fields_hash($prop);
  my (@task);
  while (my ($name, $value) = splice @_, 0, 2) {
    unless (defined $name) {
      croak "Undefined name given for @{[ref($glob)]}->configure(name=>value)!";
    }
    $name =~ s/^-//;
    if (my $sub = $glob->can("configure_$name")) {
      push @task, [$sub, $value];
    } elsif (not exists $fields->{"cf_$name"}) {
      confess "No such config item $name in class " . ref $glob;
    } else {
      $prop->{"cf_$name"} = $value;
    }
  }
  if (wantarray) {
    # To delay configure_zzz.
    @task;
  } else {
    $$_[0]->($glob, $$_[1]) for @task;
    $glob;
  }
}

sub commit {
  my PROP $prop = (my $glob = shift)->prop;
  if (my $sub = $prop->{cf_header}) {
    print {$$prop{cf_parent_fh}} $sub->($glob, @_)
      unless $prop->{header_is_printed}++;
  }
  $glob->flush;
}

sub flush {
  my PROP $prop = (my $glob = shift)->prop;
  $glob->IO::Handle::flush();
  if ($prop->{cf_parent_fh}) {
    print {$prop->{cf_parent_fh}} $prop->{buffer};
    $prop->{buffer} = '';
    $prop->{cf_parent_fh}->IO::Handle::flush();
    # XXX: flush 後は、 parent_fh の dup にするべき。
    # XXX: でも、 multipart (server push) とか continue とかは？
  }
}

1;
