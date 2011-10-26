#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/..");
use Test::More qw(no_plan);
use YATT::Lite::TestUtil;
use File::Basename;
use List::Util qw(sum);

#========================================
use YATT::Lite::Breakpoint;
use YATT::Lite::Web::Dispatcher;
use YATT::Lite::Util qw(lexpand appname);
sub MY () {__PACKAGE__}
require YATT::TestFiles;

sub myapp {join _ => MyTest => appname($0), shift}

my ($quiet, $i) = (1);
my $BASE = "/tmp/yatt-test$$.d";
my $dig = YATT::TestFiles->new($BASE
			       , quiet => $quiet, auto_clean => 1);

$i = 1;
{
  my $docs = "t$i.docs";
  $dig->mkdir($docs);
  #========================================
  my $theme = "[t$i] from dir";
  ok chdir("$BASE/$docs"), "chdir [t$i]";

  my $mux = new YATT::Lite::Web::Dispatcher->new
    (basens => myapp($i), output_encoding => 'shiftjis'
     , mount => "$BASE/$docs");

  my $text_html_sjis = qr{Content-Type: text/html; charset=shiftjis};

  # $YATT::Lite::APP が見えているかのテストのため、 &yatt:template(); を呼んでみる.
  my $gateway_interface = "CGI(local)";
  my @test = (['foo.yatt', '1st', <<END, <<END, $text_html_sjis]
AAA
<yatt:bar/>
<?yatt= __PACKAGE__?>
&yatt:template(){cf_usage};
<!yatt:widget bar>
barrrr
<!yatt:config usage="BBB">
END
AAA
barrrr
MyTest_cgi_1::INST1::ROOT::foo
BBB
END

	      , ['foo.ydo', '1st', <<'END', <<'END', $text_html_sjis]
sub {
  my ($sys, $fh) = @_;
  print $fh "ok\n";
}
END
ok
END

	      , ['foo.yatt', '2nd', <<END, <<END, $text_html_sjis]
XXX<yatt:bar/>ZZZ
<!yatt:widget bar>
yyy
END
XXXyyy
ZZZ
END

	      , ['foo.ydo', '2nd', <<'END', <<'END', $text_html_sjis]
sub {
  my ($sys, $fh) = @_;
  print $fh "okok\n";
}
END
okok
END

	      , 'BREAK'
	      , ['foo.yatt', '3rd', <<END, <<END, $text_html_sjis]
XXX<yatt:foobar/>ZZZ
<!yatt:widget foobar>
yyy
END
XXXyyy
ZZZ
END

	      # XXX: session cookie 周りは?

	      , ['redir.ydo', 'redirect', <<'END', ''
sub {
  my ($sys, $con) = @_;
  $con->redirect(\ 'http://localhost/bar/');
}
END
		 , qr{^Status: \s 302 \s (?:Moved|Found)\r?\n
		    Location: \s http://localhost/bar/\r?\n}x]

	      , ['bar.yatt', 'CON methods', <<'END', <<'END', $text_html_sjis]
&yatt:CON:mkurl();
&yatt:CON:mkurl(=undef);
&yatt:CON:mkurl(foo.yatt);
&yatt:CON:mkurl(.);
END
http://localhost/bar.yatt
http://localhost/bar.yatt
http://localhost/foo.yatt
http://localhost/
END
	     );

  foreach my $test (@test) {
    unless (defined $test and ref $test eq 'ARRAY') {
      breakpoint();
      next;
    }
    my ($fn, $title, $in, $result, $header_re) = @$test;
    $dig->add("$docs/$fn", $in);
    {
      my %env = (GATEWAY_INTERFACE => $gateway_interface
		 , REDIRECT_STATUS => 200
		 , PATH_TRANSLATED => "$BASE/$docs/$fn"
		 , REQUEST_URI => "/$fn");
      is captured_runas($mux, \ (my $header), cgi => \%env, ()), $result
	, "$theme $fn $title - redirected";
      like $header, $header_re
	, "$theme - header contains specified charset";
    }
    {
      my %env = (GATEWAY_INTERFACE => $gateway_interface
		 , DOCUMENT_ROOT => $BASE
		 , SCRIPT_NAME => "/t$i.cgi"
		 , PATH_INFO => "/$fn"
		 , REQUEST_URI => "/$fn"
		 , #XXX "$ENV{SCRIPT_NAME}$ENV{PATH_INFO}"
		 );
      is captured_runas($mux, \ (my $header), cgi => \%env, ()), $result
	, "$theme $fn $title - mounted";
      like $header, $header_re
	, "$theme - header contains specified charset";
    }
  }
}

$i++;
{
  #========================================
  # Other internal tests. Especially for CGI path setup.

  my $docs = "t$i.docs";
  $dig->mkdir($docs, my $realdir);
  $dig->mkdir("$docs/img");
  $dig->mkdir("$docs/d1");

  $dig->add("$docs/index.yatt", 'top');
  $dig->add("$docs/auth.yatt", 'auth');
  $dig->add("$docs/img/bg.png", 'background');
  $dig->add("$docs/d1/f1.yatt", 'in_d1');

  my $mux = new YATT::Lite::Web::Dispatcher->new
    (basens => myapp($i), , mount => "$BASE/$docs");

  my $P_T = "$realdir/index.yatt/foo/bar";  # path_translated
  my $R_URI = '/~hkoba/index.yatt/foo/bar'; # request_uri

  is_deeply scalar $mux->split_path_url($P_T, $R_URI)
    , {location => '/~hkoba/'
       , root => $realdir
       , dir => "$realdir/"
       , file => 'index.yatt'
       , subpath => '/foo/bar'}
      , 'split_path_url: UserDir';

  $R_URI = '/index.yatt/foo/bar';

  is_deeply scalar $mux->split_path_url($P_T, $R_URI, $realdir)
    , {location => '/'
       , root => $realdir
       , dir => "$realdir/"
       , file => 'index.yatt'
       , subpath => '/foo/bar'}
      , 'split_path_url: systemwide www';

  my $splitter = sub {
    [YATT::Lite::Util::split_path(shift, $realdir)]
  };

  is_deeply $splitter->("$realdir/auth")
    , [$realdir, "/", "auth.yatt", ""]
      , ".yatt extension compensation";

  is_deeply $splitter->("$realdir/auth/foo")
    , [$realdir, "/", "auth.yatt", "/foo"]
      , ".yatt extension compensation, with subpath";

  is_deeply $splitter->("$realdir/img/bg.png")
    , [$realdir, "/img/", "bg.png", ""]
      , "other extension";

  is_deeply $splitter->("$realdir/img/missing.png")
    , [$realdir, "/img/", "missing.png", ""]
      , "other missing.";
}


sub captured_runas {
  my ($obj, $header, $as, $env, @args) = @_;
  open my $fh, ">", \ (my $buf = "") or die $!;
  $obj->runas($as, $fh, $env, @args);
  close $fh;
  $buf =~ s/^((?:[^\n]+\n)+)\r?\n//s
    and $$header = $1;
  return $buf;
}
