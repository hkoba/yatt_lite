#!/usr/bin/env perl
package YATT::Lite::LanguageServer::Generic;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base
  , [fields =>
     , qw/_buffer _out_semaphore/
     , [read_fd => default => 0]
     , [write_fd => default => 1]
     , [read_length => default => 8192]
     , [jsonrpc_version => default => '2.0']
     , [dump_request => default => 0]
   ];

use MOP4Import::Types
  (Header => [[fields => qw/Content-Length/]]);

use YATT::Lite::LanguageServer::Protocol
  qw/Request Response Error/;

# Most logics are shamelessly stolen from Perl::LanguageServer

use Coro ;
use Coro::AIO ;
use AnyEvent;

use Scope::Guard qw/guard/;

use IO::Handle;

use URI;

#========================================

sub after_configure_default {
  (my MY $self) = @_;
  $self->{_out_semaphore} = Coro::Semaphore->new;
}

sub call_method {
  (my MY $self, my Request $request) = @_;
  my $method = $self->translate_method_name($request->{method});
  if (my $sub = $self->can($method)) {
    print STDERR "# call_method '$method': ", $self->cli_encode_json($request), "\n";
    my $params = $request->{params};
    $sub->($self, $params);
  } else {
    print STDERR "# Not implemented: ", $self->cli_encode_json($request), "\n";
    undef;
  }
}

sub translate_method_name {
  (my MY $self, my $method) = @_;
  $method =~ s,/,__,g;
  $method =~ s,^\$,__ext,;
  'lspcall__'.$method;
}

sub cmd_server {
  (my MY $self, my @args) = @_;

  autoflush STDERR 1;
  print STDERR "# server started\n" unless $self->{quiet};

  my $cv = AnyEvent::CondVar->new;

  async {
    $self->mainloop(@args);
    $cv->send;
  };

  $cv->recv;
  "";
}

sub mainloop {
  (my MY $self) = @_;
  my (%request, %notification); # XXX: should this be an instance member?
  my $notificationNo;
  while (1) {
    my $reqRaw = $self->read_raw_request or do {
      print STDERR "# empty request, skipped\n" unless $self->{quiet};
      return;
    };
    my Request $request = JSON::decode_json($reqRaw);
    if (defined (my $id = $request->{id})) {
      print STDERR "# processing request: "
        , $self->cli_encode_json($request), "\n" unless $self->{quiet};
      $request{$id} = async {
        my $guard = guard {
          delete $request{$id};
        };
        $self->process_request($id, $request);
      };
    } else {
      print STDERR "# got notification: "
        , $self->cli_encode_json($request), "\n" unless $self->{quiet};
      ++$notificationNo;
      $notification{$notificationNo} = async {
        my $guard = guard {
          delete $notification{$notificationNo};
        };
        $self->process_request(undef, $request);
      };
    }

    cede;
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
  $response->{id} = $id if defined $id;
  $response->{jsonrpc} = $self->{jsonrpc_version};

  print STDERR "# sending response: ", $self->cli_encode_json($response), "\n"
    unless $self->{quiet};

  my $wdata = $self->format_response($self->make_response($response, $id));

  my $guard = $self->{_out_semaphore}->guard;
  my $sum = 0;
  use bytes;
  while ((my $diff = length($wdata) - $sum) > 0) {
    my $cnt = aio_write $self->{write_fd}, undef, $diff, $wdata, $sum;
    die "write_error ($!)" if $cnt <= 0;
    $sum += $cnt;
  }

  print STDERR "# sent response\n" unless $self->{quiet};
}

sub make_response {
  (my MY $self, my Response $response, my $id) = @_;
  $response->{id} = $id if defined $id;
  $response->{jsonrpc} = $self->{jsonrpc_version};
  $response;
}

sub format_response {
  (my MY $self, my Response $response) = @_;
  my $outdata = $self->cli_encode_json($response);
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
  my Header $header = $self->read_header
    or return;
  defined (my $len = $header->{'Content-Length'}) or do {
    print STDERR "# No Content-Length, skippped.\n" unless $self->{quiet};
    return;
  };
  print STDERR "# enter read body.\n" unless $self->{quiet};
  while ((my $diff = $len - length $self->{_buffer}) > 0) {
    print STDERR "# start aio read body.\n" unless $self->{quiet};
    my $cnt = aio_read $self->{read_fd}, undef, $diff
      , $self->{_buffer}, length $self->{_buffer};
    print STDERR "# end aio read body. cnt=$cnt\n" unless $self->{quiet};
    return if $cnt == 0;
  }
  print STDERR "# finished read body. len=$len.\n" unless $self->{quiet};
  my $data = substr($self->{_buffer}, 0, $len, '');
  wantarray ? ($data, $header) : $data;
}

sub read_header {
  (my MY $self, my Header $header) = @_;
  $self->{_buffer} //= "";
  my $sepPos;
  do {
    print STDERR "# start aio read header.\n" unless $self->{quiet};
    my $cnt = aio_read $self->{read_fd}, undef, $self->{read_length}
      , $self->{_buffer}, length $self->{_buffer};
    print STDERR "# end aio read header."
      , " is_utf8=", (Encode::is_utf8($self->{_buffer}) ? "yes" : "no")
      , " cnt=$cnt\n"
      , ($self->{dump_request} ? $self->dump_buffer : ())
      , "\n"
      unless $self->{quiet};
    $sepPos = index($self->{_buffer}, "\r\n\r\n");
    print STDERR "sepPos=", $sepPos // "null", "\n" unless $self->{quiet};
    return if $cnt == 0;
  } until ($sepPos >= 0);
  foreach my $line (split "\r\n", substr($self->{_buffer}, 0, $sepPos)) {
    my ($k, $v) = split ": ", $line, 2;
    $header->{$k} = $v;
  }
  substr($self->{_buffer}, 0, $sepPos+4, '');
  print STDERR "# got header: "
    , $self->cli_encode_json($header), "\n" unless $self->{quiet};
  $header;
}

sub dump_buffer {
  (my MY $self) = @_;
  require Data::HexDump::XXD;

  join("\n", Data::HexDump::XXD::xxd($self->{_buffer}));
}

#----------------------------------------

sub uri2localpath {
  (my MY $self, my $uri) = @_;
  return undef unless defined $uri;
  return undef unless $uri =~ m{^file://};
  URI->new($uri)->path;
}

MY->run(\@ARGV) unless caller;

1;
