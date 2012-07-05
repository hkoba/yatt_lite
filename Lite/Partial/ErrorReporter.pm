package YATT::Lite::Partial::ErrorReporter; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw/all/;
use YATT::Lite::Partial
  (fields => [qw/cf_at_done
		 cf_error_handler
		 cf_die_in_error
		/]);
use Carp qw/longmess/;
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
  require YATT::Lite::Error;
  new YATT::Lite::Error
    (file => $opts->{file} // $file, line => $opts->{line} // $line
     , format => $fmt, args => [@_[1..$#_]]
     , backtrace => longmess()
     , $opts ? %$opts : ());
}

# $yatt->raise($errType => ?{opts}?, $errFmt, @fmtArgs)

sub raise {
  (my MY $self, my $type) = splice @_, 0, 2;
  my $opts = shift if @_ and ref $_[0] eq 'HASH';
  # shift/splice ���ʤ��Τϡ������� stack trace �˻Ĥ���������
  my $err = $self->make_error(1 + (delete($opts->{depth}) // 1), $opts, @_);

  if (ref $self and my $sub = $self->{cf_error_handler}) {
    # $con ������ǰ�������󤹤Τ����ѤʤΤǡ��ष������ closure ���Ϥ������ȡ�
    # $SIG{__DIE__} ��Ȥ�ʤ��ΤϤʤ����ä�? ����ϥ桼���˳������Ƥ��������Τ��
    $sub->($type, $err);
  } elsif ($sub = $self->can('error_handler')) {
    $sub->($self, $type, $err);
  } elsif (not ref $self or $self->{cf_die_in_error}) {
    die $err->message;
  } else {
    # ¨�¤� die ���ʤ��⡼�ɤϡ��ǥХå����� error �ƤӽФ��ս�� step ��������褦�ˤ��뤿�ᡣ
    # ... �Ǥ⡢����¦�� do {my $err = $con->error; die $err} �ˤǤ⤷�ʤ�����ᤫ��?
    return $err;
  }
}

# XXX: ���衢��ĥ����뤫�⡣
sub DONE {
  my MY $self = shift;
  if (my $sub = $self->{cf_at_done}) {
    $sub->(@_);
  } else {
    die \ 'DONE';
  }
}


1;
