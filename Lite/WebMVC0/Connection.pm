package YATT::Lite::WebMVC0::Connection; sub PROP () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Lite::Connection);
use fields qw(cf_cgi cf_dir cf_file cf_subpath cf_is_gateway
	      cf_is_psgi
	      cf_hmv
	      cf_root cf_location
	      cf_use_array_param
	    );
use YATT::Lite::Util qw(globref url_encode nonempty);
use Carp;

#----------------------------------------

BEGIN {
  # print STDERR join("\n", sort(keys our %FIELDS)), "\n";
  foreach my $name (qw(url_param request_method referer)) {
    *{globref(PROP, $name)} = sub {
      my PROP $prop = (my $glob = shift)->prop;
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

#========================================

sub param {
  my PROP $prop = (my $glob = shift)->prop;
  if (my $hmv = $prop->{cf_hmv}) {
    return $hmv->keys unless @_;
    if (@_ == 1) {
      return wantarray ? $hmv->get_all($_[0]) : $hmv->get($_[0]);
    } else {
      $hmv->add(@_);
      return $glob;
    }
  } elsif (my $cgi = $prop->{cf_cgi}) {
    return $cgi->param(@_);
  } else {
    croak "Neither Hash::Multivalue nor CGI is found in connection!";
  }
}

#========================================

sub configure_cgi {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{cf_cgi} = my $cgi = shift;
  if ($prop->{cf_use_array_param}) {
    if ($prop->{cf_is_psgi}) {
      $glob->convert_array_param_psgi($cgi);
    } else {
      $glob->convert_array_param_cgi($cgi);
    }
  }
}

sub convert_array_param_psgi {
  my ($glob, $req) = @_;
  my $params = $req->body_parameters || $req->query_parameters;
  foreach my $name (keys %$params) {
    (my $newname = $name) =~ s{^\*|\[\]$}{}
      or next;
    my %hash; $hash{$_} = 1 for $params->get_all($name);
    $params->remove($name);
    $params->add($newname, \%hash);
  }
  $req;
}

sub convert_array_param_cgi {
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

sub _invoke_or {
  my ($default, $obj, $method, @args) = @_;
  if (defined $obj and my $sub = $obj->can($method)) {
    $sub->($obj, @args)
  } else {
    $default;
  }
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

  my $scheme = $prop->{cf_env}{'psgi.url_scheme'} || $prop->{cf_cgi}->protocol;
  my $host = $glob->mkhost($scheme);
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
  my $url = '';
  if (not $opts{local}) {
    $url .= $scheme . '://' . $host;
  }
  $url .= $path . $glob->mkquery($param, $opts{separator});
  $url;
}

sub mkhost {
  my PROP $prop = (my $glob = shift)->prop;
  my ($scheme) = @_;
  $scheme ||= 'http';
  my $env = $prop->{cf_env};

  # XXX? Is this secure?
  return $env->{HTTP_HOST} if nonempty($env->{HTTP_HOST});

  my $base = $env->{SERVER_NAME}
    // _invoke_or('localhost', $prop->{cf_cgi}, 'server_name');
  if (my $port = $env->{SERVER_PORT}
      || _invoke_or(80, $prop->{cf_cgi}, 'server_port')) {
    $base .= ":$port"  unless ($scheme eq 'http' and $port == 80
			       or $scheme eq 'https' and $port == 443);
  }
  $base;
}

sub mkquery {
  my ($self, $param, $sep) = @_;
  $sep //= '&';

  my @enc_param;
  if (ref $param eq 'HASH') {
    push @enc_param, $self->url_encode($_).'='.$self->url_encode($param->{$_})
      for sort keys %$param;
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

sub list_header {
  my PROP $prop = (my $glob = shift)->prop;
  ($glob->SUPER::list_header, $glob->list_baked_cookie);
}

sub _mk_content_type {
  my PROP $prop = (my $glob = shift)->prop;
  my $ct = $prop->{cf_content_type} || "text/html";
  if ($ct =~ m{^text/} && $ct !~ /;\s*charset/) {
    my $cs = $prop->{cf_charset} || "utf-8";
    $ct .= qq|; charset=$cs|;
  }
}

sub mkheader {
  my PROP $prop = (my $glob = shift)->prop;
  my ($code) = shift;
  require HTTP::Headers;
  my $headers = HTTP::Headers->new("Content-type", $glob->_mk_content_type
				   , $glob->list_header
				   , @_);
  YATT::Lite::Util::mk_http_status($code)
      . $headers->as_string . "\015\012";
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
  wantarray ? map(("Set-Cookie", $_), @cookie) : \@cookie;
}

sub redirect {
  my PROP $prop = (my $glob = shift)->prop;
  croak "undefined url" unless @_ and defined $_[0];
  my $url = do {
    if (ref $_[0]) {
      # To do external redirect, $url should pass as SCALAR REF.
      ${shift @_}
    } elsif ($_[0] =~ m{^(?:\w+:)?//([^/]+)}
	     and $1 ne ($glob->mkhost // '')) {
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
  if ($prop->{cf_is_psgi}) {
    # PSGI mode.
    die [302, [Location => $url, $glob->list_header], []];
  } else {
    print {$fh} $glob->mkheader(302, Location => $url, @_);
    # 念のため, parent_fh は undef しておく
    undef $$prop{cf_parent_fh};
    # XXX: やっぱこっちも die すべきじゃん... なら、呼び出し手は catch 必須では？
    # => catch があるなら、 catch 側で header 出せばいいじゃん？
    # ==>> header_is_printed との関係？
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

  my $value = $glob->param($name);

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
