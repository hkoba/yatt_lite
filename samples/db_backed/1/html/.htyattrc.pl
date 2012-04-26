#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);

use fields qw(dbic
	      cf_dir_config
	      cf_datadir cf_dbname);

use YATT::Lite qw(*CON);

require CGI::Session;

sub DBIC () { __PACKAGE__ . '::DBIC' }

use YATT::Lite::WebMVC0::DBSchema::DBIC
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
      , login => ['text', -unique]
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

Entity dir_config => sub {
  my ($this, $name) = @_;
  my MY $self = $this->YATT;
  return $self->{cf_dir_config} unless defined $name;
  $self->{cf_dir_config}{$name};
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
  if ($new || $self->_session_sid($prop->{cf_cgi})) {
    $prop->{session} = $self->_load_session($con, $new, @rest);
  } else {
    $prop->{session} = undef;
  }
}

sub _session_sid {
  (my MY $self, my $cgi_or_req) = @_;
  return unless defined $cgi_or_req;
  if (my $sub = $cgi_or_req->can('cookies')) {
    $sub->($cgi_or_req)->{$self->sid_name};
  } else {
    scalar $cgi_or_req->cookie($self->sid_name);
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
    ("driver:file", $self->_session_sid($con->cget('cgi')), undef, \%opts);

  if (not $new and $sess and $sess->is_empty) {
    # die "Session is empty!";
    return
  }

  # expire させたくない時は、 session_opts に expire: 0 を仕込むこと。
  $sess->expire($expire) if $sess;

  if ($new and $sess) {
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

sub find_user_by_login {
  my ($self, $login) = @_;
  $self->dbic->resultset('user')->single({login => $login});
}

sub find_user_by_email {
  my ($self, $email) = @_;
  $self->dbic->resultset('user')
    ->search({email => $email})
      ->single;
}

sub find_user {
  my ($self, $login_or_email) = @_;
  if ($login_or_email =~ /\@/) {
    $self->find_user_by_email($login_or_email)
  } else {
    $self->find_user_by_login($login_or_email)
  }
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

sub reset_password {
  my ($self, $email, $expire_mins) = @_;
  my $dbic = $self->dbic;
  my ($auth, $token, $error);
  txn_do $dbic sub {
    unless ($auth = $self->find_user_by_email($email)) {
      $error = "Unknown email: $email";
      return;
    }

    $auth->tmppass($token = $self->make_password(20));
    $auth->tmppass_expire(time + 60*($expire_mins // 60));
    $auth->update;
  };

  die $error if $error;

  $token;
}

sub can_change_password {
  my ($self, $email, $token) = @_;
  my $auth = $self->dbic->resultset('user')
    ->search({email => $email})
      ->single
	or return;

  return unless ($auth->tmppass // '') eq $token;
  return unless time < ($auth->tmppass_expire // 0);
  $auth;
}

sub do_change_password {
  my ($self, $email, $token, $password) = @_;
  my $dbic = $self->dbic;
  my ($user, $error);
  txn_do $dbic sub {
    unless ($user = $self->can_change_password($email, $token)) {
      $error = "Invalid email or expired token!";
      return
    }
    my $auth = $user;
    $auth->update({encpass => md5_hex($password)
		   , tmppass => undef
		   , tmppass_expire => undef});
  };
  die $error if $error;
  $user;
}

sub fetch_pass_pair {
  (my MY $self, my $con) = @_;
  my $pass1 = $con->param_type('password', qr{^\w{8,}$ }x
			       , q|Password should be alphabets and digits|
			      . q|, at least 8 chars.|);
  my $pass2 = $con->param_type('password2', nonempty =>
			       , q|Please retype same password.|);

  unless ($pass1 eq $pass2) {
    die "Password mismatch!";
  }

  $pass1;
}

sub fetch_email {
  (my MY $self, my $con) = @_;
  my $email = $con->param_type
    ('email', qr{^[\w\.\-]+\@[\w\.\-]+$ }x
     , q|Email syntax error!|);
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

Entity mail_sender => sub {
  my ($this) = @_;
  $this->entity_dir_config('mail_sender') || 'webmaster@localhost';
};


#========================================

sub dbic {
  my MY $self = shift;
  $self->{dbic} //= $self->DBIC->connect($self->dbi_dsn);
}

sub dbi_dsn {
  my MY $self = shift;
  "dbi:SQLite:dbname=$self->{cf_dbname}";
}

sub cmd_setup {
  my MY $self = shift;
  unless (-d $self->{cf_datadir}) {
    require File::Path;
    File::Path::make_path($self->{cf_datadir}, {mode => 02775, verbose => 1});
  }
  # XXX: more verbosity.
  # XXX: Should be idempotent.
  # $self->dbic->YATT_DBSchema->deploy;
  $self->DBIC->YATT_DBSchema->cf_let([verbose => 1]
				     , connect_to_sqlite => $self->{cf_dbname});
}

#========================================
sub after_new {
  my MY $self = shift;
  $self->{cf_datadir} //= "$self->{cf_dir}/../data";
  $self->{cf_dbname} //= "$self->{cf_datadir}/.htdata.db";
}
