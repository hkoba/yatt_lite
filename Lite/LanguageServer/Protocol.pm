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
'ClientCapabilities' => [
  [
    'fields',
    'workspace',
    'textDocument',
    'experimental',
  ],
],
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
'TextDocumentSyncOptions' => [
  [
    'fields',
    'openClose',
    'change',
    'willSave',
    'willSaveWaitUntil',
    'save',
  ],
],
'CompletionOptions' => [
  [
    'fields',
    'resolveProvider',
    'triggerCharacters',
  ],
],
'Location' => [
  [
    'fields',
    'uri',
    'range',
  ],
],
'RenameOptions' => [
  [
    'fields',
    'prepareProvider',
  ],
],
'DocumentLinkOptions' => [
  [
    'fields',
    'resolveProvider',
  ],
],
'CodeLensOptions' => [
  [
    'fields',
    'resolveProvider',
  ],
],
'ServerCapabilities' => [
  [
    'fields',
    'textDocumentSync',
    'hoverProvider',
    'completionProvider',
    'signatureHelpProvider',
    'definitionProvider',
    'typeDefinitionProvider',
    'implementationProvider',
    'referencesProvider',
    'documentHighlightProvider',
    'documentSymbolProvider',
    'workspaceSymbolProvider',
    'codeActionProvider',
    'codeLensProvider',
    'documentFormattingProvider',
    'documentRangeFormattingProvider',
    'documentOnTypeFormattingProvider',
    'renameProvider',
    'documentLinkProvider',
    'colorProvider',
    'foldingRangeProvider',
    'executeCommandProvider',
    'workspace',
    'experimental',
  ],
],
'InitializeResult' => [
  [
    'fields',
    'capabilities',
  ],
],
'DocumentOnTypeFormattingOptions' => [
  [
    'fields',
    'firstTriggerCharacter',
    'moreTriggerCharacter',
  ],
],
'Range' => [
  [
    'fields',
    'start',
    'end',
  ],
],
'CodeActionOptions' => [
  [
    'fields',
    'codeActionKinds',
  ],
],
'SignatureHelpOptions' => [
  [
    'fields',
    'triggerCharacters',
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
'Position' => [
  [
    'fields',
    'line',
    'character',
  ],
],
'ExecuteCommandOptions' => [
  [
    'fields',
    'commands',
  ],
],
'TextDocumentPositionParams' => [
  [
    'fields',
    'textDocument',
    'position',
  ],
],
'SaveOptions' => [
  [
    'fields',
    'includeText',
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
'TextDocumentIdentifier' => [
  [
    'fields',
    'uri',
  ],
],

   #==END_GENERATED

  );


1;
