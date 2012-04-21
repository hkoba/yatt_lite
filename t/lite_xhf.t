#!/usr/bin/perl -w
# -*- coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/..");
use Test::More;
use YATT::Lite::TestUtil;
use File::Basename;
use List::Util qw(sum);
use encoding qw(:locale);

#========================================
use YATT::Lite;
use YATT::Lite::Util qw(lexpand);
use YATT::Lite::Util qw(appname);
sub myapp {join _ => MyTest => appname($0), @_}

use YATT::Lite::Breakpoint;

use YATT::Lite::XHFTest qw(Item);
use base qw(YATT::Lite::XHFTest File::Spec);
use fields qw(cf_VFS_CONFIG cf_YATT_CONFIG cf_YATT_RC);
sub MY () {__PACKAGE__}

my @files = MY->list_files(@ARGV ? @ARGV
			   : <$FindBin::Bin/xhf/*/*.xhf>);

my (@section);
foreach my $fn (@files) {
  eval {
    push @section, my MY $sect = MY->load(file => untaint_any($fn));
    if (my $cf = $sect->{cf_YATT_CONFIG} and my $enc = $sect->{cf_encoding}) {
      $sect->convert_enc_array($enc, $cf);
    }
  };
  die "Error while loading $fn: $@" if $@;
}

my $ntests = (@section * 2) + sum(map {$_->ntests} @section);
plan tests => $ntests;

my $i = 1;
foreach my MY $sect (@section) {
  my $fn = path_tail($sect->{cf_filename}, 2);
  # XXX: as_vfs_spec => data => {}, rc => '...';
  my $spec = [data => $sect->as_vfs_data];
  if (my $cf = $sect->{cf_VFS_CONFIG}) {
    push @$spec, @$cf;
  }
  ok(my $yatt = new YATT::Lite(appns => myapp($i)
			       , vfs => $spec
			       , debug_cgen => $ENV{DEBUG}
			       , debug_parser => 1
			       , lexpand($sect->{cf_YATT_CONFIG})
			       , $sect->{cf_YATT_RC}
			       ? (rc_script => $sect->{cf_YATT_RC}) : ()
			      )
     , "$fn new YATT::Lite");
  is ref $yatt, 'YATT::Lite', 'new YATT::Lite package';
  local $YATT::Lite::YATT = $yatt; # XXX: runyatt に切り替えられないか？
  my $last_title;
  foreach my Item $test (@{$sect->{tests}}) {
    next unless $test->is_runnable;
    my $title = "[$fn] " . ($test->{cf_TITLE} // $last_title
			    // $test->{cf_ERROR} // "(undef)");
    $title .= " ($test->{num})" if $test->{num};
  SKIP: {
      if ($test->{cf_SKIP}
	  and my $skip = $test->ntests) {
	skip "by SKIP: $title", $skip
	  if not $test->{cf_PERL_MINVER} or $] < $test->{cf_PERL_MINVER};
      }
      breakpoint() if $test->{cf_BREAK};
      if ($test->{cf_OUT}) {
	my $error;
	unless ($test->{realfile}) {
	  die "test realfile is undef!";
	}
	local $SIG{__DIE__} = sub {$error = @_ > 1 ? [@_] : shift};
	local $SIG{__WARN__} = sub {$error = @_ > 1 ? [@_] : shift};
	my ($pkg) = eval {
	  my $tmpl = $yatt->find_file($test->{realfile});
	  $yatt->find_product(perl => $tmpl);
	};
	is $error, undef, "$title - compiled.";
	if ($error) {
	  skip "not compiled - $title", 1;
	} else {
	  eval {
	    eq_or_diff captured($pkg => render_ => lexpand($test->{cf_PARAM}))
	      , $test->{cf_OUT}, "$title";
	  };
	  if ($@) {
	    fail "$title: runtime error: $@";
	  }
	}
      } elsif ($test->{cf_ERROR}) {
	eval {
	  my $tmpl = $yatt->find_file($test->{realfile});
	  my $pkg = $yatt->find_product(perl => $tmpl);
	  captured($pkg => render_ => lexpand($test->{cf_PARAM}));
	};
	like $@, qr{^$test->{cf_ERROR}}, $title;
      }
    }
    $last_title = $test->{cf_TITLE} if $test->{cf_TITLE};
  }
} continue { $i++ }

sub captured {
  my ($obj, $method, @args) = @_;
  open my $fh, ">", \ (my $buf = "") or die $!;
  binmode $fh, ":encoding(utf8)"; #XXX: 常に、で大丈夫なのか?
  # XXX: locale と一致しなかったらどうすんの?
  $obj->$method($fh, @args);
  close $fh;
  $buf;
}

sub path_tail {
  my $fn = shift;
  my $len = shift // 1;
  my @path = MY->splitdir($fn);
  splice @path, 0, @path - $len;
  wantarray ? @path : MY->catdir(@path);
}
