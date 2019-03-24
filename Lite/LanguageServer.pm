#!/usr/bin/env perl
package YATT::Lite::LanguageServer;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use YATT::Lite::LanguageServer::Generic -as_base
  , [fields => qw/_initialized
                  _client_cap
                 /
   ];

use YATT::Lite::LanguageServer::Protocol;

sub initialize {
  (my MY $self, my InitializeParams $params) = @_;
  $self->{_client_cap} = $params->{capabilities};
  my InitializeResult $res = {};
  $res->{capabilities} = my ServerCapabilities $svcap = {};
  $svcap->{definitionProvider} = JSON::true;
  $res;
}

sub textDocument__definition {
  (my MY $self, my TextDocumentPositionParams $params) = @_;
  die "ANOTHERRRRR";
  my TextDocumentIdentifier $docId = $params->{textDocument};
  my Position $pos = $params->{position};
  
  undef;
}

MY->run(\@ARGV) unless caller;

1;
