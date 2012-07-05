package YATT::Lite::Partial::ErrorReporter; sub MY () {__PACKAGE__}
# -*- coding: utf-8 -*-
use strict;
use warnings FATAL => qw/all/;
use YATT::Lite::Partial
  (fields => [qw/cf_at_done
		 cf_error_handler
		 cf_die_in_error
		/]);
use Carp qw/longmess/;

use YATT::Lite::Error; sub Error () {'YATT::Lite::Error'}

#========================================
# error reporting.
#========================================

sub error {
  (my MY $self) = map {ref $_ ? $_ : MY} shift;
  $self->raise(error => @_);
}

sub make_error {
  my ($self, $depth, $opts) = splice @_, 0, 3;
  my $fmt = $_[0];
  my ($pkg, $file, $line) = caller($depth);
  $self->Error->new
    (file => $opts->{file} // $file, line => $opts->{line} // $line
     , format => $fmt, args => [@_[1..$#_]]
     , backtrace => longmess()
     , $opts ? %$opts : ());
}

# $yatt->raise($errType => ?{opts}?, $errFmt, @fmtArgs)

sub raise {
  (my MY $self, my $type) = splice @_, 0, 2;
  my $opts = shift if @_ and ref $_[0] eq 'HASH';
  # shift/splice しないのは、引数を stack trace に残したいから
  my $err = $self->make_error(1 + (delete($opts->{depth}) // 1), $opts, @_);

  if (ref $self and my $sub = $self->{cf_error_handler}) {
    # $con を引数で引きずり回すのは大変なので、むしろ外から closure を渡そう、と。
    # $SIG{__DIE__} を使わないのはなぜかって? それはユーザに開放しておきたいのよん。
    $sub->($type, $err);
  } elsif ($sub = $self->can('error_handler')) {
    $sub->($self, $type, $err);
  } elsif (not ref $self or $self->{cf_die_in_error}) {
    die $err->message;
  } else {
    # 即座に die しないモードは、デバッガから error 呼び出し箇所に step して戻れるようにするため。
    # ... でも、受け側を do {my $err = $con->error; die $err} にでもしなきゃダメかも?
    return $err;
  }
}

# XXX: 将来、拡張されるかも。
sub DONE {
  my MY $self = shift;
  if (my $sub = $self->{cf_at_done}) {
    $sub->(@_);
  } else {
    die \ 'DONE';
  }
}


1;
