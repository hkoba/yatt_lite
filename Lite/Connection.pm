package YATT::Lite::Connection; sub PROP () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use fields qw(buffer header header_is_printed cookie session
	      cf_header cf_parent_fh cf_handler cf_system cf_db
	      cf_content_type
	      cf_charset
	      cf_encoding
	      cf_env
	      error_backup
	      cf_backend
	      stash
	      debug_stash
	    );
use YATT::Lite::Util qw(globref fields_hash);
use YATT::Lite::Entities qw(*SYS *YATT);
use Carp;

sub prop { my $glob = shift; \%{*$glob}; }
sub build_prop {
  my $class = shift;
  my PROP $prop = fields::new($class);
  my $fields = fields_hash($prop);
  my @task;
  while (my ($name, $value) = splice @_, 0, 2) {
    if (my $sub = $class->can("configure_$name")) {
      push @task, [$sub, $value];
    } elsif (not exists $fields->{"cf_$name"}) {
      confess "No such config item $name in class $class";
    } else {
      $prop->{"cf_$name"} = $value;
    }
  }
  wantarray ? ($prop, @task) : $prop;
}

sub build_fh_for {
  (my $class, my PROP $prop) = splice @_, 0, 2;
  unless (defined $_[0]) {
    my $enc = $$prop{cf_encoding} ? ":encoding($$prop{cf_encoding})" : '';
    open $_[0], ">$enc", \ ($prop->{buffer} = "") or die $!;
  } elsif ($$prop{cf_encoding}) {
    binmode $_[0], ":encoding($$prop{cf_encoding})";
  }
  bless $_[0], $class;
  *{$_[0]} = $prop;
  $_[0];
}

#========================================
# Constructors (create_for_yatt, new)
#========================================
# To route errors to $yatt(==DirHandler), connection needs yatt ref.
# sub create_for_yatt {
#   my ($class, $yatt, $self) = splice @_, 0, 3;
#   require IO::Handle;
#   (my PROP $prop, my @task) = $class->build_prop(@_);
#   $class->build_fh_for($prop, $self);
#   $_->[0]->($self, $_->[1]) for @task;
#   $self->after_new;
#   $self;
# }

# XXX: Should be deprecated?
sub new {
  my ($class, $self) = splice @_, 0, 2;
  require IO::Handle;
  my ($prop, @task) = $class->build_prop(@_);
  $class->build_fh_for($prop, $self);
  $_->[0]->($self, $_->[1]) for @task;
  $self->after_new;
  $self;
}

sub after_new {}

#----------------------------------------
sub error {
  shift->raise(error => @_);
}
sub raise {
  my PROP $prop = prop(my $glob = shift);
  my ($type, @err) = @_; # To make sure backtrace is meaningful.
  if (my $handler = $SYS || $YATT) {
    $handler->raise($type, @err);
  } else {
    shift @err if @err and ref $err[0] eq 'HASH'; # drop opts.
    my $fmt = shift @err;
    croak sprintf($fmt, @err);
  }
}

#========================================

sub buffer {
  my PROP $prop = prop(my $glob = shift);
  $prop->{buffer}
}

sub set_header {
  my PROP $prop = prop(my $glob = shift);
  my ($key, $value) = @_;
  $prop->{header}{$key} = $value;
  $glob;
}
sub list_header {
  my PROP $prop = prop(my $glob = shift);
  (map($_ ? %$_ : (), $prop->{header}));
}

sub content_type {
  my PROP $prop = prop(my $glob = shift);
  $prop->{cf_content_type}
}
sub set_content_type {
  my PROP $prop = prop(my $glob = shift);
  $prop->{cf_content_type} = shift;
  $glob;
}

sub charset {
  my PROP $prop = prop(my $glob = shift);
  $prop->{cf_charset}
}
sub set_charset {
  my PROP $prop = prop(my $glob = shift);
  $prop->{cf_charset} = shift;
  $glob;
}

sub cget {
  confess "Not enough argument" unless @_ == 2;
  my PROP $prop = prop(my $glob = shift);
  my $fields = YATT::Lite::Util::fields_hash($prop);
  my ($name) = @_;
  if (not exists $fields->{"cf_$name"}) {
    confess "No such config item $name in class " . ref $glob;
  }
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

sub header_is_printed {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{header_is_printed};
}

# XXX: Should be renamed to something like: finalize_header.
sub commit {
  my PROP $prop = (my $glob = shift)->prop;
  if (not $prop->{header_is_printed}++
      and my $sub = $prop->{cf_header}) {
    my @header = $sub->($glob, @_);
    #print STDERR "# HEADER: ", YATT::Lite::Util::terse_dump(\@header), "\n";
    print {$$prop{cf_parent_fh}} @header;
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

sub is_error {
  my PROP $prop = (my $glob = shift)->prop;
  defined $prop->{error_backup};
}

sub as_error {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{error_backup} = $prop->{buffer};
  $prop->{buffer} = '';
  seek $glob, 0, 0;
  $glob;
}

#----

sub backend {
  my PROP $prop = (my $glob = shift)->prop;
  my $method = shift;
  unless (defined $method) {
    $glob->error("backend: null method is called");
  } elsif (not $prop->{cf_backend}) {
    $glob->error("backend is empty");
  } elsif (not my $sub = $prop->{cf_backend}->can($method)) {
    $glob->error("unknown method called for backend: %s", $method);
  } else {
    $sub->($prop->{cf_backend}, @_);
  }
}

sub model {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{cf_backend}->model(@_);
}

1;
