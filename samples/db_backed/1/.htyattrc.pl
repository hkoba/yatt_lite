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
  my $sess = $this->YATT->get_session($CON);
  if (@_ == 1) {
    $sess->param(@_);
  } else {
    $sess->param(@_);
    $sess;
  }
};

Entity is_logged_in => sub {
  shift->YATT->get_session($CON);
};

Entity set_logged_in => sub {
  my ($this, $value) = @_;
  if ($value) {
    $this->YATT->load_session($CON);
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
  $self->load_session($con)
    if $prop->{cf_cgi}->cookie($self->sid_name);
}

sub load_session {
  (my MY $self, my $con) = @_;
  my ConnProp $prop = $con->prop;
  $prop->{session} ||= $self->load_session_for($con);
}

sub default_session_expire {'1d'}

use YATT::Lite::Util qw(lexpand);
sub load_session_for {
  (my MY $self, my $con) = @_;
  my %opts = (name => $self->sid_name, lexpand($self->{cf_session_opts}));
  my $expire = delete($opts{expire}) // $self->default_session_expire;
  my $sess = CGI::Session->new("driver:file", $con->cget('cgi'), undef, \%opts);
  # expire させたくない時は、 session_opts に expire: 0 を仕込むこと。
  $sess->expire($expire);
  $sess;
}

sub remove_session {
  (my MY $self, my $cgi_or_con) = @_;
  my @rm = ($self->sid_name, '', -expire => '-10y'); # 10年早いんだよっと。
  if ($cgi_or_con->isa(ConnProp)) {
    my ConnProp $prop = $cgi_or_con->prop;
    my $sess = delete $prop->{session} or return;
    $sess->delete;
    $sess->flush;
    $cgi_or_con->set_cookie(@rm);
  } else {
    # XXX でも、session ファイルが消されずに残るよね？
    # delete, flush すれば、ファイルは消されるらしい。
    my $sess = $self->load_session_for($cgi_or_con);
    $sess->delete;
    $sess->flush;
    ConnProp->bake_cookie(@rm);
  }
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
    or return 'No such user';
  my $auth = $user->auth
    or return 'No auth';
  return 'Password mismatch' unless $auth->encpass eq md5_hex($plain_pass);
  return undef;
}

sub add_user {
  my ($self, $login, $pass, $email) = @_;

  # tmppass と expire を生成しないと
  my $token = $self->make_password;

  my $newuser = $self->dbic->resultset('user')
    ->new({login => $login
	   , email => $email
	   , encpass => md5_hex($pass)
	   , confirm_token => $token
	  });
  # XXX: ユーザ名重複のエラー処理.

  $newuser->insert;

  $self->encrypt_password($token, $newuser->id, $pass);
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

sub sendmail {
  my ($self, $con, $page, $widget_name, $to, @rest) = @_;
  if (grep {not defined $_} $widget_name, $to) {
    die "Not enough parameter!";
  }
  my $sub = $page->can("render_$widget_name")
    or die "Unknown widget $widget_name";

  require Mail::Send;
  my $msg = new Mail::Send(To => $to);

  my $fh = $msg->open;

  $sub->($page, $fh, $to, @rest);
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
