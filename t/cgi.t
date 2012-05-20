#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}
use base qw(File::Spec);
use File::Basename;

use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
my $libdir;
BEGIN {
  unless (grep {$_ eq 'YATT'} MY->splitdir($FindBin::Bin)) {
    die "Can't find YATT in runtime path: $FindBin::Bin\n";
  }
  $libdir = dirname(dirname(untaint_any($FindBin::Bin)));
}
use lib $libdir;
#----------------------------------------

use Test::More qw(no_plan);
use YATT::Lite::Test::TestUtil;
use List::Util qw(sum);

#========================================
use YATT::Lite::Breakpoint;
use YATT::Lite::WebMVC0;
use YATT::Lite::Util qw(lexpand appname);
require YATT::Lite::Test::TestFiles;

sub myapp {join _ => MyTest => appname($0), shift}

my ($quiet, $i) = (1);
my $BASE = "/tmp/yatt-test$$.d";
my $dig = YATT::Lite::Test::TestFiles->new($BASE
				     , quiet => $quiet, auto_clean => 1);

$i = 1;
{
  my $docs = "t$i.docs";
  $dig->mkdir($docs);
  #========================================
  my $theme = "[t$i] from dir";
  ok chdir("$BASE/$docs"), "chdir [t$i]";

  my $mux = YATT::Lite::WebMVC0->new
    (app_ns => myapp($i), output_encoding => 'shiftjis'
     , app_root => $BASE
     , doc_root => "$BASE/$docs");

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
MyTest_cgi_1::INST1::EntNS::foo
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

  my $mux = YATT::Lite::WebMVC0->new
    (app_ns => myapp($i), doc_root => "$BASE/$docs");

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
