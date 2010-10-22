#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/..");
use Test::More qw(no_plan);
use Test::Differences;
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
  local $ENV{GATEWAY_INTERFACE} = "CGI(local)";
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

	      , 'BREAK'
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

	      # XXX: session cookie 周りは?

	      , ['redir.ydo', 'redirect', <<'END', ''
sub {
  my ($sys, $con) = @_;
  $con->redirect('http://localhost/bar/');
}
END
		 , qr{^Status: \s 302 \s (?:Moved|Found)\r?\n
		    Location: \s http://localhost/bar/\r?\n}x]

	     );

  foreach my $test (@test) {
    unless (defined $test and ref $test eq 'ARRAY') {
      breakpoint();
      next;
    }
    my ($fn, $title, $in, $result, $header_re) = @$test;
    $dig->add("$docs/$fn", $in);
    {
      local $ENV{REDIRECT_STATUS} = 200;
      local $ENV{PATH_TRANSLATED} = "$BASE/$docs/$fn";
      is captured_runas($mux, \ (my $header), cgi => ()), $result
	, "$theme $fn $title - redirected";
      like $header, $header_re
	, "$theme - header contains specified charset";
    }
    {
      local $ENV{DOCUMENT_ROOT} = $BASE;
      local $ENV{SCRIPT_NAME} = "/t$i.cgi";
      local $ENV{PATH_INFO} = "/$fn";
      is captured_runas($mux, \ (my $header), cgi => ()), $result
	, "$theme $fn $title - mounted";
      like $header, $header_re
	, "$theme - header contains specified charset";
    }
  }
}

sub captured_runas {
  my ($obj, $header, $as, @args) = @_;
  open my $fh, ">", \ (my $buf = "") or die $!;
  $obj->runas($as, $fh, @args);
  close $fh;
  $buf =~ s/^((?:[^\n]+\n)+)\r?\n//s
    and $$header = $1;
  return $buf;
}
