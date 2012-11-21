#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);

use fields qw(cf_datadir cf_limit);

#========================================
use Fcntl qw(:DEFAULT :flock SEEK_SET);

sub mh_alloc_newfh {
  (my MY $yatt) = @_;
  my ($fnum, $lockfh) = $yatt->mh_lastfnum(1);

  my ($fname);
  do {
    $fname = "$yatt->{cf_datadir}/.ht_" . ++$fnum;
  } while (-e $fname);

  seek $lockfh, 0, SEEK_SET
    or die "Can't seek: $!";
  print $lockfh $fnum, "\n";
  truncate $lockfh, tell($lockfh);

  open my $fh, '>', $fname
    or die "Can't open newfile '$fname': $!";

  wantarray ? ($fh, $fname, $fnum) : $fh;
}

sub mh_lastfnum {
  (my MY $yatt) = shift;
  my $lockfh = $yatt->mh_openlock(@_);
  my $num = <$lockfh>;
  if (defined $num and $num =~ /^\d+/) {
    $num = $&;
  } else {
    $num = 0;
  }
  wantarray ? ($num, $lockfh) : $num;
}

sub mh_openlock {
  (my MY $yatt, my $lock) = @_;
  my $lockfn = "$yatt->{cf_datadir}/.ht_lock";
  sysopen my $lockfh, $lockfn, O_RDWR | O_CREAT
    or die "Can't open '$lockfn': $!";

  if ($lock) {
    flock $lockfh, LOCK_EX
      or die "Can't lock '$lockfn': $!";
  }
  $lockfh;
}

#========================================

Entity mh_files => sub {
  my ($this, $opts) = @_;
  my MY $yatt = MY->YATT; # To make sure strict check occurs.
  my $as_realpath = delete $opts->{realpath};
  my $start = delete($opts->{current}) // 0;
  my $limit = delete($opts->{limit}) // $yatt->{cf_limit};
  my $ext = delete($opts->{ext}) // '';
  # XXX: $opts should be empty now.
  my @result = do {
    my @all;
    opendir my $dh, $yatt->{cf_datadir}
      or die "Can't opendir '$yatt->{cf_datadir}': $!";
    while (my $fn = readdir $dh) {
      my ($num) = $fn =~ m{^\.ht_(\d+)$ext$}
	or next;
      push @all, $as_realpath ? [$num, "$yatt->{cf_datadir}/$fn"] : $num;
    }
    closedir $dh; # XXX: Is this required still?
    $as_realpath ? map($$_[-1], sort {$$a[0] <=> $$b[0]} @all)
      : sort {$a <=> $b} @all;
  };
  unless (wantarray) {
    \@result;
  } else {
    @result[$start .. min($start+$limit, $#result)];
  }
};

Entity mh_load => sub {
  my ($this, $fnum) = @_;
  my MY $yatt = $this->YATT; # To make sure strict field check occurs.
  my $fn = "$yatt->{cf_datadir}/.ht_$fnum";
  unless (-r $fn) {
    die "Can't read '$fn'\n";
  }
  $yatt->read_file_xhf($fn, bytes => 1);
};

sub escape_nl {
  shift;
  $_[0] =~ s/\n/\n /g;
  $_[0];
}

sub min {$_[0] < $_[1] ? $_[0] : $_[1]}

sub after_new {
  my MY $self = shift;
  # $self->SUPER::after_new(); # Should call, but without this, should work.
  $self->{cf_datadir} //= '../data';
  $self->{cf_limit} //= 100;
}

1;
