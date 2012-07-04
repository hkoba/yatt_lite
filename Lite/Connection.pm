package YATT::Lite::Connection; sub PROP () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use Carp;

use Hash::Util qw/lock_keys/;

# XXX: MFields may be ok.
use fields
  (# Incoming request. Should be filled by Dispatcher(Factory)
   qw/cf_env cookies_in/

   # Outgoing response. Should be written by YATT and *.yatt
   , qw/cf_parent_fh cf_buffer
	headers header_is_sent
	cf_status cf_content_type cf_charset cf_encoding
	cookies_out/

   # To suppress HTTP header, set this.
   , 'cf_noheader'

   # To distinguish error state.
   , qw/is_error raised oldbuf/

   # Session store
   , qw/session stash debug_stash/

   # Invocation context
   , qw/cf_system cf_yatt cf_backend cf_dbh/
  );

use YATT::Lite::Util qw(globref fields_hash NIMPL);
use YATT::Lite::PSGIEnv;

sub prop { my $glob = shift; \%{*$glob}; }

#========================================
# Constructors
#========================================

sub create {
  my ($class, $self) = splice @_, 0, 2;
  require IO::Handle;
  my ($prop, @task) = $class->build_prop(@_);
  $class->build_fh_for($prop, $self);
  $_->[0]->($self, $_->[1]) for @task;
  $self->after_create;
  $self;
}

sub after_create {}

sub build_prop {
  my $class = shift;
  my $fields = fields_hash($class);
  my PROP $prop = lock_keys(my %prop, keys %$fields);
  my @task;
  while (my ($name, $value) = splice @_, 0, 2) {
    if (my $sub = $class->can("configure_$name")) {
      push @task, [$sub, $value];
    } elsif (not exists $fields->{"cf_$name"}) {
      confess "No such config item '$name' in class $class";
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
    $prop->{cf_buffer} //= (\ my $str);
    ${$prop->{cf_buffer}} //= "";
    open $_[0], ">$enc", $prop->{cf_buffer} or die $!;
  } elsif ($$prop{cf_encoding}) {
    binmode $_[0], ":encoding($$prop{cf_encoding})";
  }
  bless $_[0], $class;
  *{$_[0]} = $prop;
  $_[0];
}

sub configure_encoding {
  my PROP $prop = prop(my $glob = shift);
  my $enc = shift;
  $prop->{cf_encoding} = $enc;
  binmode $glob, ":encoding($enc)";
}

#========================================

sub cget {
  confess "Not enough argument" unless @_ == 2;
  my PROP $prop = prop(my $glob = shift);
  my $fields = fields_hash($glob);
  my ($name) = @_;
  if (not exists $fields->{"cf_$name"}) {
    confess "No such config item '$name' in class " . ref $glob;
  }
  $prop->{"cf_$name"};
}

sub configure {
  my PROP $prop = prop(my $glob = shift);
  my $fields = fields_hash($glob);
  my (@task);
  while (my ($name, $value) = splice @_, 0, 2) {
    unless (defined $name) {
      croak "Undefined name given for @{[ref($glob)]}->configure(name=>value)!";
    }
    $name =~ s/^-//;
    if (my $sub = $glob->can("configure_$name")) {
      push @task, [$sub, $value];
    } elsif (not exists $fields->{"cf_$name"}) {
      confess "No such config item '$name' in class " . ref $glob;
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

#========================================

sub as_error {
  my PROP $prop = prop(my $glob = shift);
  $prop->{is_error} = 1;
  if (my $buf = $prop->{cf_buffer}) {
    $prop->{oldbuf} = $$buf; $$buf = '';
  }
  $glob->configure(@_) if @_;
  $glob;
}

sub error {
  # XXX: as_error?
  shift->raise(error => @_);
}

sub raise {
  my PROP $prop = prop(my $glob = shift);
  my ($type, @err) = @_; # To keep args visible in backtrace.
  $prop->{raised} = $type;
  if (my $system = $prop->{cf_system}) {
    $system->raise($type, @err);
  } else {
    shift @err if @err and ref $err[0] eq 'HASH'; # drop opts.
    my $fmt = shift @err;
    croak sprintf($fmt, @err);
  }
}

#========================================

DESTROY {
  shift->flush_headers;
}

sub flush_headers {
  my PROP $prop = (my $glob = shift)->prop;

  return if $prop->{header_is_sent}++;

  $glob->finalize_headers;

  if (not $prop->{cf_noheader}) {
    my $fh = $prop->{cf_parent_fh} // $glob;
    print $fh $glob->mkheader;
  }
  $glob->flush;
}

sub finalize_headers {
  my PROP $prop = (my $glob = shift)->prop;
  $glob->finalize_cookies if $prop->{cookies_out};
  $prop->{cf_yatt}->finalize_connection($glob)   if $prop->{cf_yatt};
  $prop->{cf_system}->finalize_connection($glob) if $prop->{cf_system};
}

sub flush {
  my PROP $prop = (my $glob = shift)->prop;
  $glob->IO::Handle::flush();
  if ($prop->{cf_parent_fh}) {
    print {$prop->{cf_parent_fh}} ${$prop->{cf_buffer}};
    ${$prop->{cf_buffer}} = '';
    $prop->{cf_parent_fh}->IO::Handle::flush();
    # XXX: flush 後は、 parent_fh の dup にするべき。
    # XXX: でも、 multipart (server push) とか continue とかは？
  }
}

#========================================
# Cookie support, based on CGI::Cookie (works under PSGI mode too)

sub cookies_in {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{cookies_in} ||= do {
    my Env $env = $prop->{cf_env};
    require CGI::Cookie;
    CGI::Cookie->parse($env->{HTTP_COOKIE});
  };
}

sub set_cookie {
  my PROP $prop = (my $glob = shift)->prop;
  if (@_ == 1 and ref $_[0]) {
    my $cookie = shift;
    my $name = $cookie->name;
    $prop->{cookies_out}{$name} = $cookie;
  } else {
    my $name = shift;
    $prop->{cookies_out}{$name} = $glob->new_cookie($name, @_);
  }
}

sub new_cookie {
  my $glob = shift;		# not used.
  my ($name, $value) = splice @_, 0, 2;
  require CGI::Cookie;
  CGI::Cookie->new(-name => $name, -value => $value, @_);
}

sub finalize_cookies {
  my PROP $prop = (my $glob = shift)->prop;
  return unless $prop->{cookies_out};
  $prop->{headers}{'Set-Cookie'} = [map {"$_"} values %{$prop->{cookies_out}}];
}
#========================================

sub buffer {
  my PROP $prop = prop(my $glob = shift);
  ${$prop->{cf_buffer}}
}

sub mkheader {
  my PROP $prop = (my $glob = shift)->prop;
  my ($code) = shift // $prop->{cf_status} // 200;
  require HTTP::Headers;
  my $headers = HTTP::Headers->new("Content-type", $glob->_mk_content_type
				   , $glob->list_header
				   , @_);
  YATT::Lite::Util::mk_http_status($code)
      . $headers->as_string . "\015\012";
}

sub _mk_content_type {
  my PROP $prop = (my $glob = shift)->prop;
  my $ct = $prop->{cf_content_type} || "text/html";
  if ($ct =~ m{^text/} && $ct !~ /;\s*charset/) {
    my $cs = $prop->{cf_charset} || "utf-8";
    $ct .= qq|; charset=$cs|;
  }
  $ct;
}

sub set_header {
  my PROP $prop = prop(my $glob = shift);
  my ($key, $value) = @_;
  $prop->{headers}{$key} = $value;
  $glob;
}

sub append_header {
  my PROP $prop = prop(my $glob = shift);
  my ($key, @values) = @_;
  push @{$prop->{headers}}{$key}, @values;
}

sub list_header {
  my PROP $prop = prop(my $glob = shift);
  (map($_ ? %$_ : (), $prop->{headers}));
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

#========================================

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
