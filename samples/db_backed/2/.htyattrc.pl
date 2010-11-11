#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);

use fields qw(dbic
	      cf_datadir
	      cf_dbname cf_dbuser cf_dbpass);

use YATT::Lite qw(*CON);

require CGI::Session;

sub DBIC () { __PACKAGE__ . '::DBIC' }

use YATT::Lite::DBSchema::DBIC
  (DBIC, verbose => $ENV{DEBUG_DBSCHEMA}
   , [user => undef
      , uid => [integer => -primary_key
		, [-has_many
		   , [address => undef
		      , addrid => [integer => -primary_key]
		      , owner => [int => [-belongs_to => 'user']]
		      , country => 'text'
		      , zip => 'text'
		      , prefecture => 'text'
		      , city => 'text'
		      , address => 'text'], 'owner']
		, [-has_many
		   , [entry => undef
		      , eid => [integer => -primary_key]
		      , owner => [int => [-belongs_to => 'user']]
		      , title => 'text'
		      , text  => 'text'], 'owner']]
      , login => 'text'
      , encpass => 'text'
      , tmppass => 'text'
      , tmppass_expire => 'datetime'
      , email => 'text'
      , confirm_token => ['text', -unique]
     ]
   );

#========================================
Entity resultset => sub {
  shift->YATT->dbic->resultset(@_);
};

#========================================
Entity sess => sub {
  my ($this) = shift;
  my $sess = $this->YATT->get_session($CON)
    or return undef;
  $sess->param(@_);
};

Entity is_logged_in => sub {
  shift->YATT->get_session($CON);
};

Entity set_logged_in => sub {
  my ($this, $value, @rest) = @_;
  if ($value) {
    $this->YATT->load_session($CON, 1, @rest);
  } else {
    $this->YATT->remove_session($CON);
  }
};

use YATT::Lite::Types
  (['ConnProp']);

sub sid_name {'SID'}

sub get_session {
  (my MY $self, my $con) = @_;
  my ConnProp $prop = $con->prop;
  if (exists $prop->{session}) {
    $prop->{session};
  } else {
    $self->load_session($con);
  }
}

sub load_session {
  (my MY $self, my ($con, $new, @rest)) = @_;
  my ConnProp $prop = $con->prop;
  if ($new || $prop->{cf_cgi}->cookie($self->sid_name)) {
    $prop->{session} = $self->_load_session($con, $new, @rest);
  } else {
    $prop->{session} = undef;
  }
}

use YATT::Lite::Util qw(lexpand ostream);
sub default_session_expire {'1d'}
sub _load_session {
  (my MY $self, my ($con, $new, @rest)) = @_;
  my $method = $new ? 'new' : 'load';
  my %opts = (name => $self->sid_name, lexpand($self->{cf_session_opts}));
  my $expire = delete($opts{expire}) // $self->default_session_expire;
  my $sess = CGI::Session->$method
    ("driver:file", $con->cget('cgi'), undef, \%opts);

  if (not $new and $sess->is_empty) {
    # die "Session is empty!";
    return
  }

  # expire させたくない時は、 session_opts に expire: 0 を仕込むこと。
  $sess->expire($expire);

  if ($new) {
    # 本当に良いのかな?
    $con->set_cookie($sess->cookie(-path => $con->location));

    while (my ($name, $value) = splice @rest, 0, 2) {
      $sess->param($name, $value);
    }
  }

  $sess;
}

sub remove_session {
  (my MY $self, my $con) = @_;
  my $sess = $self->get_session($con)
    or return;

  my ConnProp $prop = $con->prop;
  undef $prop->{session};

  $sess->delete;
  $sess->flush;
  # -expire じゃなく -expires.
  my @rm = ($self->sid_name, '', -expires => '-10y'
	    , -path => $con->location); # 10年早いんだよっと。
  $con->set_cookie(@rm);
}

#========================================
use Digest::MD5 qw(md5_hex);

sub is_user {
  my ($self, $loginname) = @_;
  $self->dbic->resultset('user')->single({login => $loginname})
}

sub has_auth_failure {
  my ($self, $loginname, $plain_pass) = @_;
  my $user = $self->dbic->resultset('user')->single({login => $loginname})
    or return "No such user: $loginname";
  return 'Password mismatch' unless $user->encpass eq md5_hex($plain_pass);
  return undef;
}

sub add_user {
  my ($self, $login, $pass, $email) = @_;

  # XXX: Is this good token?
  my $token = $self->encrypt_password
    ($self->make_password, $login, $pass);

  my $newuser = $self->dbic->resultset('user')
    ->new({login => $login
	   , email => $email
	   , encpass => md5_hex($pass)
	   , confirm_token => $token
	   # XXX: tmppass_expire
	  });

  $newuser->insert;

  ($newuser, $token);
}

# Stolen from Slash/Utility/Data/Data.pm:changePassword
{
  my @chars = grep !/[0O1Iil]/, 0..9, 'A'..'Z', 'a'..'z';
  sub make_password {
    my ($self, $len) = @_;
    return join '', map { $chars[rand @chars] } 1 .. ($len // 8);
  }

  sub encrypt_password {
    my ($self, @rest) = @_;
    md5_hex(join ":", reverse @rest);
  }
}

#========================================
use YATT::Lite::XHF qw(parse_xhf);
use YATT::Lite::Util qw(terse_dump);

sub output_file {
  my ($fn) = @_;
  open my $fh, '>', $fn or die "Can't open file '$fn': $!";
  $fh;
}

sub sendmail {
  my ($self, $con, $page, $widget_name, $to, @rest) = @_;
  if (grep {not defined $_} $widget_name, $to) {
    die "Not enough parameter!";
  }
  my $sub = $page->can("render_$widget_name")
    or die "Unknown widget $widget_name";

  my $transport = $ENV{EMAIL_SENDER_TRANSPORT};
  my $is_debug = defined $transport && $transport eq 'YATT_TEST';

  my $fh = $is_debug ? output_file("$self->{cf_datadir}/.htdebug.eml")
    : ostream(my $buffer);

  $sub->($page, $fh, $to, @rest);

  if ($is_debug) {
    return 'ok';
  } else {
    require Email::Simple;
    require Email::Sender::Simple;
    my $msg = Email::Simple->new($buffer);

    Email::Sender::Simple->send($msg);
  }
}

#========================================

sub dbic {
  my MY $self = shift;
  $self->{dbic} //= do {
    my ($dbi, $user, $pass) = $self->dbi_dsn;
    $self->DBIC->connect
      ($dbi, $user, $pass
       , {PrintError => 0, RaiseError => 1, AutoCommit => 0});
  };
}

sub dbi_dsn {
  my MY $self = shift;
  my $dsn = "dbi:mysql:database=$self->{cf_dbname}";
  wantarray ? ($dsn, $self->{cf_dbuser}, $self->{cf_dbpass}) : $dsn;
}

sub cmd_setup {
  my MY $self = shift;
  unless (-d $self->{cf_datadir}) {
    require File::Path;
    File::Path::make_path($self->{cf_datadir}, {mode => 02775, verbose => 1});
  }
  $self->DBIC->YATT_DBSchema->cf_let
    ([verbose => $ENV{VERBOSE} // 1, auto_create => 1
      , coltype_map => {text => 'varchar(80)'}]
     , connect_to => $self->dbi_dsn);
}

#========================================
sub after_new {
  my MY $self = shift;

  my $passfile = "$self->{cf_dir}/.htdbpass";
  unless (-e $passfile) {
    die "Can't find $passfile";
  }
  unless (-r $passfile) {
    die "Can't read $passfile";
  }

  $self->cf_by_filetype(xhf => $passfile);

  $self->{cf_datadir} //= "$self->{cf_dir}/data";
}
