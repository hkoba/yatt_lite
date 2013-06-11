package YATT::Lite::Partial::ErrorReporter; sub MY () {__PACKAGE__}
# -*- coding: utf-8 -*-
use strict;
use warnings FATAL => qw/all/;
use YATT::Lite::Partial
  (fields => [qw/cf_at_done
		 cf_error_handler
		 cf_die_in_error
		 cf_ext_pattern
		/]);
require Devel::StackTrace;

use YATT::Lite::Error; sub Error () {'YATT::Lite::Error'}
use YATT::Lite::Util qw/incr_opt/;


#========================================
# error reporting.
#========================================

sub error {
  (my MY $self) = map {ref $_ ? $_ : MY} shift;
  $self->raise(error => incr_opt(depth => \@_), @_);
}

sub make_error {
  my ($self, $depth, $opts) = splice @_, 0, 3;
  my $fmt = $_[0];
  my ($pkg, $file, $line) = caller($depth);
  my $bt = do {
    my @bt_opts = (ignore_package => __PACKAGE__);
    if (my $frm = delete $opts->{ignore_frame}) {
      # $YATT::Lite::CON->logdump(ignore_frame => $frm);
      push @bt_opts, frame_filter => sub {
	my ($hash) = @_;
	my $caller = $hash->{'caller'};
	my $res = not not grep {($frm->[$_] // '') ne ($caller->[$_] // '')}
	  0..2;
	# $YATT::Lite::CON->logdump(frame_filter_res => $res, $caller);
	$res;
      }
    }
    Devel::StackTrace->new(@bt_opts);
  };

  my $pattern = $self->{cf_ext_pattern} // qr/\.(yatt|ytmpl|ydo)$/;

  my @tmplinfo;
  foreach my $fr ($bt->frames) {
    my $fn = $fr->filename
      or next;
    $fn =~ $pattern
      or next;
    push @tmplinfo, tmpl_file => $fn, tmpl_line => $fr->line;
    last;
  }

  $self->Error->new
    (file => $opts->{file} // $file, line => $opts->{line} // $line
     , @tmplinfo
     , format => $fmt, args => [@_[1..$#_]]
     , backtrace => $bt
     , $opts ? %$opts : ());
}

# $yatt->raise($errType => ?{opts}?, $errFmt, @fmtArgs)

sub raise {
  (my MY $self, my $type) = splice @_, 0, 2;
  my $opts = shift if @_ and ref $_[0] eq 'HASH';
  # shift/splice しないのは、引数を stack trace に残したいから
  my $depth = (delete($opts->{depth}) // 0);
  my $err = $self->make_error(2 + $depth, $opts, @_); # 2==raise+make_error
  if (ref $self and my $sub = deref($self->{cf_error_handler})) {
    # $con を引数で引きずり回すのは大変なので、むしろ外から closure を渡そう、と。
    # $SIG{__DIE__} を使わないのはなぜかって? それはユーザに開放しておきたいのよん。
    unless (ref $sub eq 'CODE') {
      die "error_handler is not a CODE ref: $sub";
    }
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

sub deref {
  return undef unless defined $_[0];
  if (ref $_[0] eq 'REF' or ref $_[0] eq 'SCALAR') {
    ${$_[0]};
  } else {
    $_[0];
  }
}

1;
