package
  t_regist;

use strict;
use warnings FATAL => qw(all);
use utf8;
use sigtrap die => qw(normal-signals);

use Encode;
use encoding qw(:_get_locale_encoding);
#use encoding qw(:locale), map {$_ => _get_locale_encoding()} qw(STDOUT STDERR);
# binmode STDERR, sprintf ":encoding(%s)", _get_locale_encoding();

use YATT::Lite::Web::Dispatcher;
use YATT::Lite::TestUtil;
use Test::More;
use YATT::Lite::Util qw(lexpand);

sub do_test {
  my ($pack, $appdir, %opts) = @_;

  # XXX: Should directly read 1-basic.xhf first paragraph.
  foreach my $mod (qw(Plack
		      DBIx::Class::Schema
		      DBD::mysql
		      CGI::Session
		      Email::Simple
		      Email::Sender
		    )
		   , lexpand(delete $opts{REQUIRE})) {
    unless (eval qq|require $mod|) {
      skip(all => "$mod is not installed");
    }
  }

  plan tests => 4;

  my $app = YATT::Lite::Web::Dispatcher->new
    (appns => 'MyApp'
     , appdir => $appdir
     , document_root => "$appdir/html"
    );

  $pack->cleanup_sql($app, $appdir, <<END);
delete from user where login = 'hkoba'
END

  my $email_fn = "$appdir/data/.htdebug.eml";

  unlink $email_fn if -e $email_fn;

  my $got = nocr($app->render('/regist.yatt', {back => 'index.yatt'}));

  eq_or_diff($got, <<'END', 'regist.yatt');
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
<head>
  <title>Registration Form</title>
  <link rel="stylesheet" type="text/css" href="main.css">
</head>
<body>
<div id="wrapper">
  <center>
<div id="body">
  <div id="topnav">
    <h2>Registration Form</h2>
  </div>
      <form method="POST">
  <table>
    <tr>
      <th>User ID:</th>
      <td><input type="text" name="login" size="15"></td>
    </tr>
    <tr>
      <th>Password:</th>
      <td><input type="password" name="password" size="15"></td>
    </tr>
    <tr>
      <th>(Retype password):</th>
      <td><input type="password" name="password2" size="15"></td>
    </tr>
    <tr>
      <th>Email:</th>
      <td><input type="text" name="email" size="30"></td>
    </tr>
    <tr>
      <td colspan="2">
        <input type="hidden" name="back" value="index.yatt"/>
        <input type="submit" name="!regist"/>
      </td>
    </tr>
  </table>
</form>    
</div>
</center>
</div>
</div>
</body>
</html>
END

  local $ENV{EMAIL_SENDER_TRANSPORT} = 'YATT_TEST';
  $got = nocr($app->render(['/regist.yatt', undef, 'regist']
			   , {qw(login     hkoba
				 password  foo
				 password2 foo
				 email     hkoba@foo.bar
				 back      index.yatt)}));

  eq_or_diff($got, <<'END', 'regist.yatt !regist');
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
<head>
  <title></title>
  <link rel="stylesheet" type="text/css" href="main.css">
</head>
<body>
<div id="wrapper">
  <center>
<div id="body">
  <div id="topnav">
    <h2></h2>
  </div>
        <h2>Confirmation Email is Sent to you.</h2>
  <a href="index.yatt">back</a>    
</div>
</center>
</div>
</div>
</body>
</html>
END


  my $email = read_file($email_fn);

  my $theme = "email contents";
  if ($email =~ m{
\Qご登録、ありがとうございます。登録を承認する場合は
下のリンクをクリックしてください。

Thank you for registration. To confirm your registration,
please click following link:

\Ehttp://localhost/(?:[^/]+/)*regist\.yatt\?!confirm=1[;&]token=(?<token>[0-9a-f]+)\Q

心当たりの無い方は、このメールは破棄してください。

If you have received this mail without having requested it,
please dispose this mail.
\E}) {
    my $token = $+{token};

    ok(1, $theme);

    $got = nocr($app->render(['/regist.yatt', undef, 'confirm']
			     , {token => $token}));

    eq_or_diff($got, <<'END', "confirm token=$token");
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
<head>
  <title></title>
  <link rel="stylesheet" type="text/css" href="main.css">
</head>
<body>
<div id="wrapper">
      <div class="login">
      <b>hkoba</b> | <a href="logout.ydo?nx=regist.yatt">logout</a>
    </div>
  <center>
<div id="body">
  <div id="topnav">
    <h2></h2>
  </div>
        <h2>Welcome! Your registration is successfully completed.</h2>
  <a href="./">Top</a>    
</div>
</center>
</div>
</div>
</body>
</html>
END

  } else {
    fail $theme;
    if (not defined $email) {
      diag "Email was undef"
    } else {
      diag "Email was: ". encode(_get_locale_encoding(), $email);
    }
  }

  unlink $email_fn if -e $email_fn;
}

sub read_file {
  my ($fn) = @_;
  open my $fh, '<:encoding(utf8)', $fn or die "Can't open '$fn': $!";
  local $/;
  my $data = <$fh>;
  $data =~ s/\r//g;
  $data;
}

sub nocr {
  my ($res) = @_;
  $res =~ s/\r//g;
  $res =~ s/\n+$/\n/;
  $res;
}

1;
