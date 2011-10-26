package YATT::Lite::Web::Connection; sub PROP () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Lite::Connection);
use fields qw(cf_cgi cf_dir cf_file cf_subpath cf_is_gateway
	      cf_psgi
	      cf_root cf_location
	      cf_use_array_param
	    );
use YATT::Lite::Util qw(globref url_encode);
use Carp;

#----------------------------------------

BEGIN {
  # print STDERR join("\n", sort(keys our %FIELDS)), "\n";
  foreach my $name (qw(param url_param request_method header referer)) {
    *{globref(PROP, $name)} = sub {
      my PROP $prop = (my $glob = shift)->prop;
      $prop->{cf_cgi}->$name(@_);
    };
  }
  foreach my $name (qw(file subpath)) {
    my $cf = "cf_$name";
    *{globref(PROP, $name)} = sub {
      my PROP $prop = (my $glob = shift)->prop;
      $prop->{$cf};
    };
  }
}

sub configure_cgi {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{cf_cgi} = my $cgi = shift;
  $glob->convert_array_param($cgi) if $prop->{cf_use_array_param};
}

sub convert_array_param {
  my ($glob, $cgi) = @_;
  foreach my $name ($cgi->param) {
    (my $newname = $name) =~ s{^\*|\[\]$}{}
      or next;
    my %hash; $hash{$_} = 1 for $cgi->param($name);
    $cgi->delete($name);
    $cgi->param($newname, \%hash);
  }
  $cgi;
}

sub commit {
  my PROP $prop = (my $glob = shift)->prop;
  # print STDERR "committing\n", Carp::longmess(), "\n\n";
  $glob->flush_session unless $prop->{header_is_printed};
  $glob->SUPER::commit;
}

sub location {
  my PROP $prop = (my $glob = shift)->prop;
  (my $loc = ($prop->{cf_location} // '')) =~ s,/*$,/,;
  $loc;
}

# XXX: parameter の加減算も？
# XXX: 絶対 path/相対 path の選択?
# scheme
# authority
# path
# query
# fragment
sub mkurl {
  my PROP $prop = (my $glob = shift)->prop;
  my $opts = shift if @_ && ref $_[0] eq 'HASH';
  my ($file, $param, %opts) = @_;

  my $scheme = $prop->{cf_cgi}->protocol;
  my $base = $prop->{cf_cgi}->server_name;
  if (my $port = $prop->{cf_cgi}->server_port) {
    $base .= ":$port"  unless ($scheme eq 'http' and $port == 80
			       or $scheme eq 'https' and $port == 443);
  }
  my $req  = $glob->request_path;
  (my $dir  = $req) =~ s{([^/]+)$}{};
  my $orig = $1 // '';

  my $path = $dir . do {
    if (not defined $file or $file eq '') {
      $orig;
    } elsif ($file eq '.') {
      ''
    } else {
      $file;
    }
  };

  # XXX: /../ truncation
  # XXX: If sep is '&', scalar ref quoting is required.
  ($scheme . '://' . $base . $path . $glob->mkquery($param, $opts{separator}))
}

sub mkquery {
  my ($self, $param, $sep) = @_;
  $sep //= '&';

  my @enc_param;
  if (ref $param eq 'HASH') {
    push @enc_param, $self->url_encode($_).'='.$self->url_encode($param->{$_})
      for keys %$param;
  } elsif (ref $param eq 'ARRAY') {
    my @list = @$param;
    while (my ($key, $value) = splice @list, 0, 2) {
      push @enc_param, $self->url_encode($key).'='.$self->url_encode($value);
    }
  }

  unless (@enc_param) {
    wantarray ? () : '';
  } else {
    wantarray ? @enc_param : '?'.join($sep, @enc_param);
  }
}

sub request_path {
  (my $uri = shift->request_uri // '') =~ s/\?.*//;
  $uri;
}

sub request_uri {
  my PROP $prop = (my $glob = shift)->prop;
  if ($prop->{cf_env}) {
    $prop->{cf_env}{REQUEST_URI};
  } elsif ($prop->{cf_cgi}
      and my $sub = $prop->{cf_cgi}->can('request_uri')) {
    $sub->($prop->{cf_cgi});
  } else {
    $ENV{REQUEST_URI};
  }
}

#========================================

# XXX: Should not depend raw HTTP header.
sub mkheader {
  my PROP $prop = (my $glob = shift)->prop;
  # my $o = $prop->{session} || $cgi;
  my @header_param = ($glob->list_header, @_);
  if (my $cgi = $prop->{cf_cgi}) {
    my @h;
    while (my ($k, $v) = splice @header_param, 0, 2) {
      push @h, $k =~ /^-/ ? $k : "-$k", $v;
    }
    $cgi->header(@h);
  } else {
    my @out = ("Content-type: text/html");
    while (my ($key, $val) = splice @header_param, 0, 2) {
      # XXX: escape
      push @out, "X$key: $val";
    }
    join("\015\012", @out, '', '');
  }
}

#----------------------------------------

sub flush_session {
  my PROP $prop = (my $glob = shift)->prop;
  return unless $prop->{session};
  return if $prop->{session}->errstr; # XXX: to avoid double error;
  $prop->{session}->flush;
  if (my $err = $prop->{session}->errstr) {
    # To avoid infinite recursion of (error > commit > flush > error).
    $glob->session_raise(error => "Can't flush session: %s", $err);
  }
}

# flush_session will be called from $con->commit.
sub session_raise {
  my PROP $prop = (my $glob = shift)->prop;
  my ($kind, $msg, @args) = @_;
  local $prop->{session};
  $glob->raise($kind, $msg, @args);
}

#----------------------------------------

sub bake_cookie {
  my $glob = shift;		# not used.
  my ($name, $value) = splice @_, 0, 2;
  require CGI::Cookie;
  CGI::Cookie->new(-name => $name, -value => $value, @_);
}

sub set_cookie {
  my PROP $prop = (my $glob = shift)->prop;
  if (@_ == 1 and ref $_[0]) {
    my $cookie = shift;
    my $name = $cookie->name;
    $prop->{cookie}{$name} = $cookie;
  } else {
    my $name = shift;
    $prop->{cookie}{$name} = $glob->bake_cookie($name, @_);
  }
}

sub list_baked_cookie {
  my PROP $prop = (my $glob = shift)->prop;
  my @cookie = values %{$prop->{cookie}} if $prop->{cookie};
  return unless @cookie;
  wantarray ? (-cookie => \@cookie) : \@cookie;
}

sub redirect {
  my PROP $prop = (my $glob = shift)->prop;
  croak "undefined url" unless @_ and defined $_[0];
  my $url = do {
    if (ref $_[0]) {
      ${shift @_}
    } elsif ($_[0] =~ m{^(?:\w+:)?//}) {
      $glob->error("External redirect is not allowed: %s", $_[0]);
    } else {
      # taint check
      shift;
    }
  };
  if ($prop->{header_is_printed}++) {
    die "Can't redirect multiple times!";
  }

  # Make sure session is flushed before redirection.
  $glob->flush_session;

  $prop->{buffer} = '';
  # In test, parent_fh may undef.
  my $fh = $$prop{cf_parent_fh} // $glob;
  if ($prop->{cf_psgi}) {
    # PSGI mode.
    my $cookie = $glob->list_baked_cookie;
    die [302, [Location => $url, $glob->list_header
	      , $cookie ? map(("Set-Cookie", $_), @$cookie) : ()
	      ], []];
  } else {
    print {$fh} $prop->{cf_cgi}->redirect(-uri => $url
					  , $glob->list_baked_cookie, @_);
    # 念のため, parent_fh は undef しておく
    undef $$prop{cf_parent_fh};
  }
  $glob;
}

#========================================

sub param_type {
  my PROP $prop = (my $glob = shift)->prop;
  my $name = shift // croak "Undefined name!";
  my $type = shift // croak "Undefined type!";
  my $diag = shift;
  my $opts = shift;
  my $pat = ref $type eq 'Regexp' ? $type : do {
    my $pat_sub = $glob->can("re_$type")
      or croak "Unknown type: $type";
    $pat_sub->();
  };

  my $value = $prop->{cf_cgi}->param($name);

  if (defined $value && $value =~ $pat) {
    return $&; # Also for taint check.
  } elsif ($diag) {
    $glob->error((ref $diag eq 'CODE' ? $diag->($value) : $diag)
		 , $name, $value);
  } elsif (not defined $value) {
    return undef if $opts->{allow_undef};
    $glob->error("Parameter '%s' is missing!", $name);
  } else {
    # Just for default message. Production code should provide $diag.
    $glob->error("Parameter '%s' must match %s!: '%s'"
		, $name, $type, $value);
  }
}

# XXX: These should be easily extendable from .htyattrc.pl

sub re_integer { qr{^[1-9]\d*$}; }

sub re_word { qr{^\w+$}; }

sub re_nonempty { qr{\S.*}s }

sub re_any { qr{^.*$}s }

1;
