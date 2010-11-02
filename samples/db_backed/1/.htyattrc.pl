#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);

use fields qw(dbic
	      cf_datadir cf_dbname);

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
      , confirm_token => 'text'
      , tmppass => 'text'
      , tmppass_expire => 'datetime'
      , email => 'text'
      , email_verified => 'int'
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

  # expire ���������ʤ����ϡ� session_opts �� expire: 0 ��Ź��ळ�ȡ�
  $sess->expire($expire);

  if ($new) {
    # �������ɤ��Τ���?
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
  # -expire ����ʤ� -expires.
  my @rm = ($self->sid_name, '', -expires => '-10y'
	    , -path => $con->location); # 10ǯ�ᤤ�����äȡ�
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

  # tmppass �� expire ���������ʤ���
  my $token = $self->make_password;

  my $newuser = $self->dbic->resultset('user')
    ->new({login => $login
	   , email => $email
	   , encpass => md5_hex($pass)
	   , confirm_token => $token
	  });
  # XXX: �桼��̾��ʣ�Υ��顼����.

  $newuser->insert;

  ($newuser, $self->encrypt_password($token, $newuser->id, $pass));
}

# Stolen from Slash/Utility/Data/Data.pm:changePassword
{
  my @chars = grep !/[0O1Iil]/, 0..9, 'A'..'Z', 'a'..'z';
  sub make_password {
    my ($self, $len) = @_;
    return join '', map { $chars[rand @chars] } 1 .. ($len // 8);
  }

  sub encrypt_password {
    my ($self, $password, $uid, $salt) = @_;
    md5_hex("$salt:$uid:$password");
  }
}

#========================================
use YATT::Lite::XHF qw(parse_xhf);
use YATT::Lite::Util qw(terse_dump);

sub sendmail {
  my ($self, $con, $page, $widget_name, $to, @rest) = @_;
  if (grep {not defined $_} $widget_name, $to) {
    die "Not enough parameter!";
  }
  my $sub = $page->can("render_$widget_name")
    or die "Unknown widget $widget_name";

  $sub->($page, ostream(my $buffer), $to, @rest);

  my ($header, $body) = split /(?:\r?\n){2,}/, $buffer, 2;

  # die terse_dump(parse_xhf($header));
  my %header = parse_xhf($header);

  require MIME::Lite;
  my $msg = new MIME::Lite(map(($_, $header{$_}), qw(From To Subject))
			   , Data => $body);
  if (my $h = $header{'Content-type'}) {
    $msg->attr('content-type', $h);
  }

  $msg->send;
}

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
  $self->DBIC->YATT_DBSchema->connect_sqlite($self->{cf_dbname});
}

#========================================
sub after_new {
  my MY $self = shift;
  $self->{cf_datadir} //= 'data';
  $self->{cf_dbname} //= "$self->{cf_datadir}/.htdata.db";
}