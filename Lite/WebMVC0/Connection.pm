package YATT::Lite::WebMVC0::Connection; sub PROP () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use Carp;

use base qw(YATT::Lite::Connection);
use fields qw/cf_cgi
	      cf_is_psgi cf_hmv

	      cf_site_prefix

	      cf_dir cf_file cf_subpath
	      cf_root cf_location

	      current_user
	    /;
use YATT::Lite::Util qw(globref url_encode nonempty lexpand);
use YATT::Lite::PSGIEnv;

#----------------------------------------

BEGIN {
  # print STDERR join("\n", sort(keys our %FIELDS)), "\n";
  foreach my $name (qw(url_param request_method)) {
    *{globref(PROP, $name)} = sub {
      my PROP $prop = (my $glob = shift)->prop;
      $prop->{cf_cgi}->$name;
    };
  }

  foreach my $item ([referer => 'HTTP_REFERER']) {
    my ($method, $env) = @$item;
    *{globref(PROP, $method)} = sub {
      my PROP $prop = (my $glob = shift)->prop;
      $prop->{cf_env}->{$env};
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

sub queryobj {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{cf_hmv} || $prop->{cf_cgi};
}

#========================================

sub configure_cgi {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{cf_cgi} = my $cgi = shift;
  #if ($prop->{cf_use_array_param}) {
    if ($prop->{cf_is_psgi}) {
      $glob->convert_array_param_psgi($cgi);
    } else {
      $glob->convert_array_param_cgi($cgi);
    }
  #}
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

# Location(path part of url) of overall SiteApp.
sub site_location {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{cf_site_prefix} . '/';
}
*site_loc = *site_location; *site_loc = *site_location;
sub site_prefix {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{cf_site_prefix};
}

# Location of DirApp
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
  my ($orig, $dir) = ('');
  if (($dir = $req) =~ s{([^/]+)$}{}) {
    $orig = $1;
  }

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
  my ($fkeys, $fgetall);
  if (not defined $param or not ref $param) {
    return wantarray ? () : '';
    # nop
  }

  if (UNIVERSAL::isa($param, ref $self)) {
    # $CON->mkquery($CON) == $CON->mkquery($CON->queryobj)
    $param = $param->queryobj;
  }

  if ($fkeys = UNIVERSAL::can($param, 'keys')
      and $fgetall = UNIVERSAL::can($param, 'get_all')
      or ($fkeys = $fgetall = UNIVERSAL::can($param, 'param'))) {
    foreach my $key (YATT::Lite::Util::unique($fkeys->($param))) {
      my $enc = $self->url_encode($key);
      push @enc_param, "$enc=".$self->url_encode($_)
	for $fgetall->($param, $key);
    }
  } elsif (ref $param eq 'HASH') {
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

sub redirect {
  my PROP $prop = (my $glob = shift)->prop;
  croak "undefined url" unless @_ and defined $_[0];
  my $url = do {
    if (ref $_[0]) {
      # To do external redirect, $url should pass as SCALAR REF.
      my $arg = shift;
      # die "redirect url is not a scalar ref: $arg";
      $$arg;
    } elsif ($_[0] =~ m{^(?:\w+:)?//([^/]+)}
	     and $1 ne ($glob->mkhost // '')) {
      die $glob->error("External redirect is not allowed: %s", $_[0]);
    } else {
      # taint check
      shift;
    }
  };
  if ($prop->{header_is_sent}++) {
    die "Can't redirect multiple times!";
  }

  # Make sure session is flushed before redirection.
  $glob->finalize_headers;

  ${$prop->{cf_buffer}} = '';

  die [302, [Location => $url, $glob->list_header], []];
}

#========================================
# Session support is delegated to 'system'.
# 'system' must implement session_{start,resume,flush,destroy}

# To avoid confusion against $system->session_$verb,
# connection side interface is named ${verb}_session.

sub get_session {
  my PROP $prop = (my $glob = shift)->prop;
  # To avoid repeative false session tests.
  if (exists $prop->{session}) {
    $prop->{session};
  } else {
    $prop->{cf_system}->session_resume($glob);
  }
}

sub start_session {
  my PROP $prop = (my $glob = shift)->prop;
  if (defined (my $sess = $prop->{session})) {
    die $glob->error("load_session is called twice! sid=%s", $sess->id);
  }
  $prop->{cf_system}->session_start($glob, @_);
}

sub delete_session {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{cf_system}->session_delete($glob);
}

sub flush_session {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{cf_system}->session_flush($glob);
}

#========================================

sub current_user {
  my PROP $prop = (my $glob = shift)->prop;
  my $cu = do {
    if (exists $prop->{current_user}) {
      $prop->{current_user}
    } elsif (defined $prop->{cf_system}) {
      $prop->{current_user} = $prop->{cf_system}->load_current_user($glob);
    } else {
      $prop->{current_user} = undef;
    }
  };

  return $cu unless @_;
  die $glob->error("current_user is empty") unless defined $cu;
  my $method = shift;

  $cu->$method(@_);
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
    die $glob->error((ref $diag eq 'CODE' ? $diag->($value) : $diag)
		     , $name, $value);
  } elsif (not defined $value) {
    return undef if $opts->{allow_undef};
    die $glob->error("Parameter '%s' is missing!", $name);
  } else {
    # Just for default message. Production code should provide $diag.
    die $glob->error("Parameter '%s' must match %s!: '%s'"
		     , $name, $type, $value);
  }
}

# XXX: These should be easily extendable from .htyattrc.pl

sub re_integer { qr{^(?:0|[1-9]\d*)$}; }

sub re_word { qr{^\w+$}; }

sub re_nonempty { qr{\S.*}s }

sub re_any { qr{^.*$}s }

#========================================

sub accept_language {
  my PROP $prop = (my $glob = shift)->prop;
  my (%opts) = @_;
  my $filter = delete $opts{filter};
  my $detail = delete $opts{detail};
  my $long   = delete $opts{long};
  if (keys %opts) {
    die $glob->error("Unknown option for accept_language: %s"
		     , join ", ", keys %opts);
  }

  my Env $env = $prop->{cf_env};
  my $langlist = $env->{HTTP_ACCEPT_LANGUAGE}
    or return;
  my @langlist = sort {
    $$b[-1] <=> $$a[-1]
  } map {
    my ($lang, $qual) = split /\s*;\s*q=/;
    [$lang, $qual // 1]
  } split /\s*,\s*/, $langlist;

  if ($filter) {
    my $filtsub = do {
      if (ref $filter eq 'CODE') {
	$filter
      } elsif (ref $filter eq 'Regexp') {
	sub { grep {$$_[0] =~ $filter} @_ }
      } elsif (ref $filter eq 'HASH') {
	sub { grep {$filter->{$$_[0]}} @_ }
      } elsif (ref $filter eq 'ARRAY') {
	my $hash = +{map {$_ => 1} lexpand($filter)};
	sub { grep {$hash->{$$_[0]}} @_ }
      } else {
	die $glob->error("Unknown filter type for accept_language");
      }
    };
    @langlist = $filtsub->(@langlist);
  }

  if ($detail) {
    @langlist
  } else {
    if ($long) {
      # en-US => en_US
      $$_[0] =~ s/-/_/g for @langlist;
    } else {
      # en-US => en
      $$_[0] =~ s/-.*// for @langlist;
    }
    my %dup;
    wantarray ? (map {$dup{$$_[0]}++ ? () : $$_[0]} @langlist)
      : $langlist[0][0];
  }
}

1;
