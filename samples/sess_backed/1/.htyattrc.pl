use strict;
use fields qw(cf_datadir cf_config);
use YATT::Lite qw(*CON);
Entity YATT => sub {shift->YATT};

#========================================
Entity config => sub {
  my ($this) = shift;
  my MY $yatt = $this->YATT;
  if (@_) {
    $yatt->{cf_config}->{$_[0]};
  } else {
    $yatt->{cf_config};
  }
};

#========================================
require CGI::Session;

Entity sess => sub {
  my ($this) = shift;
  my $sess = $this->YATT->get_session
    or return undef;
  $sess->param(@_);
};

use YATT::Lite::Util qw(symtab);
foreach my $name (grep {/^session_/} keys %{symtab(MY)}) {
  my $copy = $name;
  Entity $name => sub {
    shift->YATT->$name(@_);
    ''; # Return empty text.
  };
}

sub sid_name {'SID'}

use YATT::Lite::Types
  (['ConnProp']);

sub get_session {
  (my MY $self) = @_;
  my ConnProp $prop = $CON->prop;
  # To avoid repeative false session tests.
  if (exists $prop->{session}) {
    $prop->{session};
  } else {
    $prop->{session} = $self->session_start_if_exists;
  }
}

use YATT::Lite::Util qw(lexpand);
sub default_session_expire {'1d'}
sub session_start_if_exists {
  (my MY $self) = shift;
  my ConnProp $prop = $CON->prop;
  $prop->{session} = $self->_session_start;
}
sub session_start_from_param {
  (my MY $self) = shift;
  my ConnProp $prop = $CON->prop;
  $prop->{session} = $self->_session_start(1, qr/^\w+$/);
}

sub _session_sid {
  (my MY $self, my $cgi_or_req) = @_;
  if (my $sub = $cgi_or_req->can('cookies')) {
    $sub->($cgi_or_req)->{$self->sid_name};
  } else {
    scalar $cgi_or_req->cookie($self->sid_name);
  }
}

sub _session_start {
  (my MY $self, my ($new, @rest)) = @_;
  my $method = $new ? 'new' : 'load';
  my %opts = (name => $self->sid_name, lexpand($self->{cf_session_opts}));
  my $expire = delete($opts{expire}) // $self->default_session_expire;
  my $sess = CGI::Session->$method
    ("driver:file", $self->_session_sid($CON->cget('cgi'))
     , undef, \%opts);

  if (not $new and $sess and $sess->is_empty) {
    # die "Session is empty!";
    return
  }

  # expire させたくない時は、 session_opts に expire: 0 を仕込むこと。
  $sess->expire($expire);

  if ($new) {
    # 本当に良いのかな?
    $CON->set_cookie($sess->cookie(-path => $CON->location));

    # Make sure session is clean state.
    $sess->clear;
    foreach my $spec (@rest) {
      if (ref $spec eq 'ARRAY') {
	my ($name, @value) = @$spec;
	$sess->param($name, @value > 1 ? \@value : $value[0]);
      } elsif (ref $spec eq 'Regexp') {
	foreach my $name ($CON->param) {
	  next unless $name =~ $spec;
	  my (@value) = $CON->param($name);
	  $sess->param($name, @value > 1 ? \@value : $value[0]);
	}
      }
    }
  }

  $sess;
}

sub session_destroy {
  (my MY $self) = @_;
  my $sess = $self->get_session
    or return;

  my ConnProp $prop = $CON->prop;
  undef $prop->{session};

  $sess->delete;
  $sess->flush;
  # -expire じゃなく -expires.
  my @rm = ($self->sid_name, '', -expires => '-10y'
	    , -path => $CON->location); # 10年早いんだよっと。
  $CON->set_cookie(@rm);
}

#========================================
use Fcntl qw(:DEFAULT :flock SEEK_SET);

sub mh_alloc_newfh {
  (my MY $yatt) = @_;
  my ($fnum, $lockfh) = $yatt->mh_lastfnum(1);

  my ($fname);
  do {
    $fname = "$yatt->{cf_datadir}/.ht_" . ++$fnum;
  } while (-e $fname);

  seek $lockfh, 0, SEEK_SET
    or die "Can't seek: $!";
  print $lockfh $fnum, "\n";
  truncate $lockfh, tell($lockfh);

  open my $fh, '>', $fname
    or die "Can't open newfile '$fname': $!";

  wantarray ? ($fh, $fname, $fnum) : $fh;
}

sub mh_lastfnum {
  (my MY $yatt) = shift;
  my $lockfh = $yatt->mh_openlock(@_);
  my $num = <$lockfh>;
  if (defined $num) {
    # chomp $num;
    $num = ($num =~ m{^(\d+)} ? $1 : 0);
  } else {
    $num = 0;
  }
  wantarray ? ($num, $lockfh) : $num;
}

sub mh_openlock {
  (my MY $yatt, my $lock) = @_;
  my $lockfn = "$yatt->{cf_datadir}/.ht_lock";
  sysopen my $lockfh, $lockfn, O_RDWR | O_CREAT
    or die "Can't open '$lockfn': $!";

  if ($lock) {
    flock $lockfh, LOCK_EX
      or die "Can't lock '$lockfn': $!";
  }
  $lockfh;
}

#########################################
Entity tsvfile => sub {
  my ($this, $name) = @_;
  my MY $yatt = $this->YATT;
  $name =~ s;(^|/)\.+/;$1;g;
  my $fn = "$yatt->{cf_dir}/$name.tsv";
  unless (-r $fn) {
    die "No such file: $fn\n";
  }
  open my $fh, '<', $fn or die "Can't open $fn: $!";
  local $_;
  my @lines;
  while (<$fh>) {
    chomp; s/\r$//;
    next if /^\#/;
    # XXX: Untaint?
    push @lines, [split /\t/];
  }
  wantarray ? @lines : \@lines;
};

#########################################
sub after_new {
  my MY $self = shift;
  $self->{cf_datadir} //= "$self->{cf_dir}/data";
}

sub cmd_setup {
  my MY $self = shift;
  unless (-d $self->{cf_datadir}) {
    require File::Path;
    File::Path::make_path($self->{cf_datadir}, {mode => 02775, verbose => 1});
  }
}
