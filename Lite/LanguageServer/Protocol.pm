package YATT::Lite::LanguageServer::Protocol;
use strict;
use warnings qw(FATAL all NONFATAL misc);

# Import 'import' to make types exportable.
use MOP4Import::Declare::Type -as_base;

use MOP4Import::Types
  (Message => [[fields => qw/jsonrpc/],
               ['subtypes',
                Request  => [[fields => qw/id method params/]],
                Response => [[fields => qw/id result error/]],
                Notification => [[fields => qw/method params/]],
              ]],
   Error => [[fields => qw/code message data/]],

   #==BEGIN_GENERATED
'InitializeParams' => [
  [
    'fields',
    'processId',
    'rootUri',
    'initializationOptions',
    'capabilities',
    'trace',
    'workspaceFolders',
  ],
],
'TextDocumentClientCapabilities' => [
  [
    'fields',
    'synchronization',
    'completion',
    'hover',
    'signatureHelp',
    'references',
    'documentHighlight',
    'documentSymbol',
    'formatting',
    'rangeFormatting',
    'onTypeFormatting',
    'declaration',
    'definition',
    'typeDefinition',
    'implementation',
    'codeAction',
    'codeLens',
    'documentLink',
    'colorProvider',
    'rename',
    'publishDiagnostics',
    'foldingRange',
  ],
],
'WorkspaceClientCapabilities' => [
  [
    'fields',
    'applyEdit',
    'workspaceEdit',
    'didChangeConfiguration',
    'didChangeWatchedFiles',
    'symbol',
    'executeCommand',
    'workspaceFolders',
    'configuration',
  ],
],
'ClientCapabilities' => [
  [
    'fields',
    'workspace',
    'textDocument',
    'experimental',
  ],
],

   #==END_GENERATED

  );


1;
