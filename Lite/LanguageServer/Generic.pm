#!/usr/bin/env perl
package YATT::Lite::LanguageServer::Generic;
use strict;
use warnings;
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base
  , [fields =>
       , qw/_buffer/
       , [read_fd => default => 0]
       , [write_fd => default => 1]
       , [read_length => default => 8192]
     ];

use MOP4Import::Types
  (Header => [[fields => qw/Content-Length/]]);

# Most logics are shamelessly stolen from Perl::LanguageServer

use Coro ;
use Coro::AIO ;
use AnyEvent;

sub make_response {
  (my MY $self, my $outdata) = @_;
  if (Encode::is_utf8($outdata)) {
    Encode::_utf8_off($outdata);
  }
  my $len = length $outdata;
  my @out = ("Content-Length: $len"
               , "Content-Type: application/vscode-jsonrpc; charset=utf-8"
               , ""
               , $outdata);
  wantarray ? @out : join("\r\n", @out);
}

sub read_raw_request {
  (my MY $self) = @_;
  my Header $header = $self->read_header;
  my $len = $header->{'Content-Length'};
  while ((my $diff = $len - length $self->{_buffer}) > 0) {
    print STDERR "# start aio read.\n" unless $self->{quiet};
    my $cnt = aio_read $self->{read_fd}, undef, $diff
      , $self->{_buffer}, length $self->{_buffer};
    print STDERR "# end aio read. cnt=$cnt\n" unless $self->{quiet};
    return if $cnt == 0;
  }
  substr($self->{_buffer}, 0, $len, '');
}

sub read_header {
  (my MY $self, my Header $header) = @_;
  $self->{_buffer} //= "";
  my $sepPos;
  do {
    print STDERR "# start aio read.\n" unless $self->{quiet};
    my $cnt = aio_read $self->{read_fd}, undef, $self->{read_length}
      , $self->{_buffer}, length $self->{_buffer};
    print STDERR "# end aio read. cnt=$cnt\n" unless $self->{quiet};
    return if $cnt == 0;
  } until (($sepPos = index($self->{_buffer}, "\r\n\r\n")) >= 0);
  foreach my $line (split "\r\n", substr($self->{_buffer}, 0, $sepPos)) {
    my ($k, $v) = split ": ", $line, 2;
    $header->{$k} = $v;
  }
  substr($self->{_buffer}, 0, $sepPos+4, '');
  $header;
}

MY->run(\@ARGV) unless caller;

1;
