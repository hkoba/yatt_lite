#!/usr/bin/env perl
package YATT::Lite::LanguageServer;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use YATT::Lite::LanguageServer::Generic -as_base
  , [fields => qw/_initialized
                  _client_cap
                  _inspector
                  _current_workspace
                 /
   ];

use MOP4Import::Util qw/terse_dump/;

use YATT::Lite::LanguageServer::Protocol;

use YATT::Lite::Inspector [as => 'Inspector'], qw/Zipper AltNode/;

sub lspcall__initialize {
  (my MY $self, my InitializeParams $params) = @_;
  $self->{_client_cap} = $params->{capabilities};

  if (my $path = $self->uri2localpath($params->{rootUri})) {
    $self->load_inspector($self->{_current_workspace} = $path);
  }

  my InitializeResult $res = {};
  $res->{capabilities} = my ServerCapabilities $svcap = {};
  $svcap->{definitionProvider} = JSON::true;
  $svcap->{hoverProvider} = JSON::true;
  $res;
}

#
# WIP
#
sub lspcall__textDocument__hover {
  (my MY $self, my TextDocumentPositionParams $params) = @_;

  my Hover $result = {};

  my TextDocumentIdentifier $docId = $params->{textDocument};
  my $fn = $self->uri2localpath($docId->{uri});
  my Position $pos = $params->{position};

  my ($innerMost, @parent) = $self->inspector->locate_node_at_file_position(
    $fn, $pos->{line}, $pos->{character}
  );

  my $lineInfo = "line $pos->{line} col $pos->{character}";

  (my AltNode $next, my $note) = do {
    if (ref $innerMost eq 'HASH') {
      ($innerMost, '');
    } elsif (ref $innerMost eq 'ARRAY' and @parent and
             ref $parent[0] eq 'HASH') {
      ($parent[0], '(not a leaf)');
    } else {
      ();
    }
  };

  if ($next) {
    $result->{range} = $next->{range};
    $result->{contents} = "$lineInfo: "
      .terse_dump($next->{kind}, $next->{path})." $note";
  } else {
    $result->{contents} = "$lineInfo: (none)";
  }

  $result;
}

#
# WIP:
#
sub lspcall__textDocument__definition {
  (my MY $self, my TextDocumentPositionParams $params) = @_;
  # print STDERR "# definition: ".terse_dump($params), "\n";
  my TextDocumentIdentifier $docId = $params->{textDocument};
  my Position $pos = $params->{position};
  my Location $res = {};
  $res->{uri} = $docId->{uri};
  $res->{range} = my Range $range = {};
  $range->{start} = do {
    my Position $p = {};
    $p->{line} = 0; $p->{character} = 0;
    $p;
  };
  $range->{end} = do {
    my Position $p = {};
    $p->{line} = 0; $p->{character} = 0;
    $p;
  };

  $res;
}

#----------------------------------------

sub inspector {
  (my MY $self) = @_;
  $self->load_inspector($self->{_current_workspace});
}

sub load_inspector {
  (my MY $self, my $rootPath) = @_;
  $self->{_inspector}{$rootPath} //= do {
    $self->Inspector->new(dir => $rootPath);
  };
}


#----------------------------------------

MY->run(\@ARGV) unless caller;

1;
