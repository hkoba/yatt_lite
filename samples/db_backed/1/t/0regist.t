#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use utf8;

use Test::Differences;
use Test::More;

sub untaint_any {$_[0] =~ m{(.*)} and $1}
use File::Basename;
use File::Spec;
my ($bindir, $libdir);
use lib untaint_any
  (File::Spec->rel2abs
   ($libdir = ($bindir = dirname(untaint_any($0)))
    . "/../../../../runyatt.lib"));

use YATT::Lite::TestFCGI;

my $CLASS = YATT::Lite::TestFCGI::Auto->class
  or YATT::Lite::TestFCGI::Auto->skip_all
  ('None of FCGI::Client and /usr/bin/cgi-fcgi is available');

# XXX: Should directly read 1-basic.xhf first paragraph.
foreach my $mod (qw(Test::Differences
		    DBIx::Class::Schema
		    CGI::Session
		    Email::Simple
		    Email::Sender
		    )) {
  unless (eval qq|require $mod|) {
    $CLASS->skip_all("$mod is not installed");
  }
}

my $mech = $CLASS->new
  (map {
    (rootdir => $_
     , fcgiscript => "$_/cgi-bin/runyatt.fcgi")
  } File::Spec->rel2abs("$bindir/.."));

if (my $reason = $mech->check_skip_reason) {
  $mech->skip_all($reason);
}

my $email_fn = "$bindir/../data/.htdebug.eml";

unlink $email_fn if -e $email_fn;

# Before fork!
$ENV{EMAIL_SENDER_TRANSPORT} = 'YATT_TEST';
$mech->fork_server;

$mech->plan('no_plan');

$mech->request(GET => '/regist.yatt', {back => 'index.yatt'});

eq_or_diff($mech->content_nocr, <<'END', 'regist.yatt');
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

$mech->request(POST => '/regist.yatt'
		 , {qw(login     hkoba
		       password  foo
		       password2 foo
		       email     hkoba@foo.bar
		       back      index.yatt
		       !regist   1)});

eq_or_diff($mech->content_nocr, <<'END', 'regist.yatt !regist');
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

http://localhost//regist.yatt?!confirm=1;token=\E(?<token>[0-9a-f]+)\Q

心当たりの無い方は、このメールは破棄してください。

If you have received this mail without having requested it,
please dispose this mail.
\E}) {
  ok(1, $theme);

  print "# token=$+{token}\n";

  $mech->request(GET => '/regist.yatt', {'!confirm' => 1
					 , token => $+{token}});

  eq_or_diff($mech->content_nocr, <<'END', 'confirm');
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
}

unlink $email_fn if -e $email_fn;

sub read_file {
  my ($fn) = @_;
  open my $fh, '<:encoding(utf8)', $fn or die "Can't open '$fn': $!";
  local $/;
  my $data = <$fh>;
  $data =~ s/\r//g;
  $data;
}