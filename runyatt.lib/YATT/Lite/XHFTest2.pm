package YATT::Lite::XHFTest2;
use strict;
use warnings FATAL => qw(all);
use Exporter qw(import);

sub Tests () {__PACKAGE__}
use base qw(YATT::Lite::Object);
use fields qw(files cf_dir cf_libdir);
use YATT::Lite::Types
  (export_default => 1
   , [File => -fields => [qw(cf_file items
			     cf_REQUIRE cf_USE_COOKIE)]]
   , [Item => -fields => [qw(cf_TITLE cf_FILE cf_METHOD cf_ACTION
			     cf_PARAM cf_HEADER cf_BODY cf_ERROR)]]);

our @EXPORT;
push @EXPORT, qw(trimlast nocr);

use Carp;
use Test::More;
use Test::Differences;
use File::Basename;
use List::Util qw(sum);

use YATT::Lite::Util qw(lexpand untaint_any);

push @EXPORT, qw(plan is is_deeply like eq_or_diff sum);

sub load_tests {
  my ($pack, $spec) = splice @_, 0, 2;
  my Tests $tests = $pack->new(@$spec);
  foreach my $fn ($tests->list_xhf(@_)) {
    push @{$tests->{files}}, $tests->load_file($fn);
  }
  $tests;
}

sub enter {
  (my Tests $tests) = @_;
  unless (defined $tests->{cf_dir}) {
    croak "dir is undef";
  }
  chdir $tests->{cf_dir} or die "Can't chdir to '$tests->{cf_dir}': $!";
}

sub test_plan {
  my Tests $self = shift;
  unless ($self->{files} and @{$self->{files}}) {
    return skip_all => "No t/*.xhf are defined";
  }
  foreach my File $file (@{$self->{files}}) {
    foreach my $req (lexpand($file->{cf_REQUIRE})) {
      unless (eval qq{require $req}) {
	return skip_all => "$req is not installed.";
      }
    }
  }
  (tests => $self->ntests);
}

use YATT::Lite::Util qw(ckdo);
sub load_dispatcher {
  my Tests $self = shift;
  (my $cgi = $self->{cf_libdir}) =~ s/\.\w+$/.cgi/;
  ckdo $cgi;
}

sub ntests {
  my Tests $tests = shift;
  sum(map {$tests->ntests_per_file($_)} @{$tests->{files}});
}

sub ntests_per_file {
  (my Tests $tests, my File $file) = @_;
  sum(map {$tests->ntests_per_item($_)} @{$file->{items}});
}

sub ntests_per_item {
  (my Tests $tests, my Item $item) = @_;
  $item->{cf_ACTION} ? 0 : 1;
}

sub file_title {
  (my Tests $tests, my File $file) = @_;
  join ';', $tests->{cf_dir}, basename($file->{cf_file});
}

sub mkpat_by {
  (my Tests $tests, my $sep) = splice @_, 0, 2;
  my $str = join $sep, map {ref $_ ? @$_ : $_} @_;
  qr{$str}sm;
}

sub mkpat { shift->mkpat_by('|', @_) }
sub mkseqpat { shift->mkpat_by('.*?', @_) }

sub list_xhf {
  my $pack = shift;
  unless (@_) {
    <*.xhf>
  } else {
    map {
      -d $_ ? <$_/*.xhf> : $_
    } @_;
  }
}

use YATT::Lite::XHF;
sub Parser {'YATT::Lite::XHF'}
sub load_file {
  my ($pack, $fn) = splice @_, 0, 2;
  _with_loading_file {$pack} $fn, sub {
    my File $file = $pack->File->new(file => $fn);
    my $parser = $pack->Parser->new(file => $fn);
    if (my @global = $parser->read) {
      $file->configure(@global);
    }
    while (my @config = $parser->read) {
      push @{$file->{items}}, $pack->Item->new(@config);
    }
    $file;
  };
}

#========================================
use 5.010;

sub mechanized {
  (my Tests $tests, my $mech) = @_;
  foreach my File $sect (@{$tests->{files}}) {
    my $dir = $tests->{cf_dir};
    my $sect_name = $tests->file_title($sect);
    foreach my Item $item (@{$sect->{items}}) {

      if (my $action = $item->{cf_ACTION}) {
	my ($method, @args) = @$action;
	my $sub = $tests->can("action_$method")
	  or die "No such action: $method";
	$sub->($tests, @args);
	next;
      }

      my $method = $tests->item_method($item);
      my $res = $tests->mech_request($mech, $item);

      if ($item->{cf_HEADER} and my @header = @{$item->{cf_HEADER}}) {
	while (my ($key, $pat) = splice @header, 0, 2) {
	  my $title = "[$sect_name] HEADER $key of $method $item->{cf_FILE}";
	  if ($res) {
	    like $res->header($key), qr{$pat}s, $title;
	  } else {
	    fail "$title - no \$res";
	  }
	}
      }

      if ($item->{cf_BODY}) {
	if (ref $item->{cf_BODY}) {
	  like nocr($mech->content), $tests->mkseqpat($item->{cf_BODY})
	    , "[$sect_name] BODY of $method $item->{cf_FILE}";
	} else {
	  eq_or_diff trimlast(nocr($mech->content)), $item->{cf_BODY}
	    , "[$sect_name] BODY of $method $item->{cf_FILE}";
	}
      } elsif ($item->{cf_ERROR}) {
	like $mech->content, qr{$item->{cf_ERROR}}
	  , "[$sect_name] ERROR of $method $item->{cf_FILE}";
      }
    }
  }
}

sub item_method {
  (my Tests $tests, my ($item)) = @_;
  $item->{cf_METHOD} // 'GET';
}

sub mech_request {
  (my Tests $tests, my ($mech, $item)) = @_;
  my $url = $tests->item_url($item);
  given ($tests->item_method($item)) {
    when ('GET') {
      return $mech->get($url);
    }
    when ('POST') {
      return $mech->post($url, $item->{cf_PARAM});
    }
    default {
      die "Unknown test method: $_\n";
    }
  }
}

sub item_url {
  (my Tests $tests, my Item $item) = @_;
  join '?', $tests->item_url_file($item), $tests->item_query($item);
}

sub item_url_file {
  (my Tests $tests, my Item $item) = @_;
  $tests->base_url . $item->{cf_FILE}
}

sub item_query {
  (my Tests $tests, my Item $item) = @_;
  return unless $item->{cf_PARAM};
  join('&', map {
    "$_=".$item->{cf_PARAM}{$_}
  } keys %{$item->{cf_PARAM}});
}

#========================================
sub action_remove {
  my Tests $tests = shift;
  my @files = glob(shift);
  unlink map {untaint_any($_)} @files if @files;
}

#========================================
sub trimlast {
  return undef unless defined $_[0];
  $_[0] =~ s/\s+$/\n/g;
  $_[0];
}

sub nocr {
  return undef unless defined $_[0];
  $_[0] =~ s|\r||g;
  $_[0];
}

1;
