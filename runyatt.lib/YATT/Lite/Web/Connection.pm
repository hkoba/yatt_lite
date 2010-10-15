package YATT::Lite::Web::Connection; sub PROP () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Lite::Connection);
use fields qw(cf_cgi cf_file cf_trailing_path);
use YATT::Lite::Util qw(globref);

sub commit {
  my PROP $prop = (my $glob = shift)->prop;
  if (my $sub = $prop->{cf_header}) {
    print {$$prop{cf_parent_fh}} $sub->($glob)
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

#----------------------------------------

BEGIN {
  # print STDERR join("\n", sort(keys our %FIELDS)), "\n";
  foreach my $name (qw(param request_method header)) {
    *{globref(PROP, $name)} = sub {
      my PROP $prop = (my $glob = shift)->prop;
      $prop->{cf_cgi}->$name(@_);
    };
  }
  foreach my $name (qw(file)) {
    my $cf = "cf_$name";
    *{globref(PROP, $name)} = sub {
      my PROP $prop = (my $glob = shift)->prop;
      $prop->{$cf};
    };
  }
}

sub cgi_url {
  my PROP $prop = (my $glob = shift)->prop;
  $prop->{cf_cgi}->url(map {$_ => 1} @_);
}
sub request_uri {
  my PROP $prop = (my $glob = shift)->prop;
  if (my $sub = $prop->{cf_cgi}->can('request_uri')) {
    $sub->($prop->{cf_cgi})
  } else {
    $ENV{REQUEST_URI};
  }
}
sub bake_cookie {
  my $glob = shift;		# not used.
  my ($name, $value) = splice @_, 0, 2;
  require CGI::Cookie;
  CGI::Cookie->new(-name => $name, -value => $value, @_);
}
sub set_cookie {
  my PROP $prop = (my $glob = shift)->prop;
  my $name = shift;
  $prop->{cookie}{$name} = $glob->bake_cookie($name, @_);
}
sub list_baked_cookie {
  my PROP $prop = (my $glob = shift)->prop;
  my @cookie = values %{$prop->{cookie}} if $prop->{cookie};
  if (my $sess = $prop->{session}) {
    push @cookie, $glob->bake_cookie($sess->name, $sess->id);
  }
  return unless @cookie;
  wantarray ? (-cookie => \@cookie) : \@cookie;
}
sub redirect {
  my PROP $prop = (my $glob = shift)->prop;
  if ($prop->{header_is_printed}++) {
    die "Can't redirect multiple times!";
  }
  $prop->{buffer} = '';
  # In test, parent_fh may undef.
  my $fh = $$prop{cf_parent_fh} // $glob;
  print {$fh} $prop->{cf_cgi}->redirect
    (-uri => shift, $glob->list_baked_cookie, @_);
  # 念のため, parent_fh は undef しておく
  undef $$prop{cf_parent_fh};
  $glob;
}

1;
