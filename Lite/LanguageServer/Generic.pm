#!/usr/bin/env perl
package YATT::Lite::LanguageServer::Generic;
use strict;
use warnings;
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base
  , [fields =>
       , qw/_buffer _out_semaphore/
       , [read_fd => default => 0]
       , [write_fd => default => 1]
       , [read_length => default => 8192]
       , [jsonrpc_version => default => '2.0']
     ];

use MOP4Import::Types
  (Header => [[fields => qw/Content-Length/]]);

use YATT::Lite::LanguageServer::Protocol;

# Most logics are shamelessly stolen from Perl::LanguageServer

use Coro ;
use Coro::AIO ;
use AnyEvent;

use Scope::Guard;

#========================================

sub after_after_new {
  (my MY $self) = @_;
  $self->{_out_semaphore} = Coro::Semaphore->new;
}

sub call_method {
  (my MY $self, my Request $request) = @_;
  my $method = $self->translate_method_name($request->{method});
  if (my $sub = $self->can($method)) {
    $sub->($self, $request);
  } else {
    print STDERR "# Not implemented: ", $self->cli_encode_json($request), "\n";
  }
}

sub translate_method_name {
  (my MY $self, my $method) = @_;
  $method =~ s,/,__,g;
  $method =~ s,^\$,__ext__,;
  $method;
}

sub server {
  (my MY $self) = @_;
  my %request; # XXX: should be an instance member?
  while (1) {
    my $reqRaw = $self->read_raw_request;
    my Request $request = JSON::decode_json($reqRaw);

    if (my $id = $request->{id}) {
      $request{$id} = async {
        my $guard = guard {
          delete $request{$id};
        };
        $self->process_request($id, $request);
      };
    } else {
      # XXX: notification
    }
  }
}

#========================================

sub process_request {
  (my MY $self, my $id, my Request $request) = @_;
  my Response $outdata;
  eval {
    $outdata->{result} = $self->call_method($request);
  };
  if (my $msg = $@) {
    $outdata->{error} = my Error $error = {};
    $error->{code} = -32001;
    $error->{message} = $msg;
  }
  if ($outdata) {
    $self->emit_response($outdata, $request->{id});
  }
}

sub emit_response {
  (my MY $self, my Response $response, my $id) = @_;
  $response->{id} = $id;
  $response->{jsonrpc} = $self->{jsonrpc_version};

  my $wdata = $self->make_response($self->cli_encode_json($response));

  my $guard = $self->{_out_semaphore}->guard;
  my $sum = 0;
  use bytes;
  while ($sum < length $wdata) {
    my $cnt = aio_write $self->{write_fd}, undef, undef, $wdata, $sum;
    die "write_error ($!)" if $cnt <= 0;
    $sum += $cnt;
  }

  print STDERR "# sent response\n" unless $self->{quiet};
}

sub make_response {
  (my MY $self, my $outdata) = @_;
  if (Encode::is_utf8($outdata)) {
    Encode::_utf8_off($outdata);
  }
  use bytes;
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
