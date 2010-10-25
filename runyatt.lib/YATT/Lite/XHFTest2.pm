package YATT::Lite::XHFTest2;
use strict;
use warnings FATAL => qw(all);
use Exporter qw(import);

sub Tests () {__PACKAGE__}
use base qw(YATT::Lite::Object);
use fields qw(files cf_dir cf_libdir);
use YATT::Lite::Types
  (export_default => 1
   , [File => -fields => [qw(cf_file items)]]
   , [Item => -fields => [qw(cf_TITLE cf_FILE cf_METHOD cf_ACTION
			     cf_PARAM cf_HEADER cf_BODY cf_ERROR)]]);

our @EXPORT;
push @EXPORT, qw(trimlast nocr);

use Carp;
use Test::More;
use Test::Differences;
use File::Basename;
use List::Util qw(sum);

use YATT::Lite::Util qw(untaint_any);

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
    return skip_all => "No t/*.xhf is defined";
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
  my File $file = $pack->File->new(file => $fn);
  my $parser = $pack->Parser->new(file => $fn);
  if (my @global = $parser->read) {
    $file->configure(@global);
  }
  while (my @config = $parser->read) {
    push @{$file->{items}}, $pack->Item->new(@config);
  }
  $file;
}

#========================================
sub action_remove {
  my Tests $tests = shift;
  my @files = glob(shift);
  unlink map {untaint_any($_)} @files if @files;
}

#========================================
sub trimlast {
  $_[0] =~ s/\s+$/\n/g;
  $_[0];
}

sub nocr {
  $_[0] =~ s|\r||g;
  $_[0];
}

1;
