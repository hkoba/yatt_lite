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
# make_typedefs_from: InitializeParams InitializeResult TextDocumentPositionParams Location Hover MarkupContent
'ClientCapabilities' => [
  [
    'fields',
    'workspace',
    'textDocument',
    'experimental',
  ],
],
'CodeActionOptions' => [
  [
    'fields',
    'codeActionKinds',
  ],
],
'CodeLensOptions' => [
  [
    'fields',
    'resolveProvider',
  ],
],
'CompletionOptions' => [
  [
    'fields',
    'resolveProvider',
    'triggerCharacters',
  ],
],
'DocumentLinkOptions' => [
  [
    'fields',
    'resolveProvider',
  ],
],
'DocumentOnTypeFormattingOptions' => [
  [
    'fields',
    'firstTriggerCharacter',
    'moreTriggerCharacter',
  ],
],
'ExecuteCommandOptions' => [
  [
    'fields',
    'commands',
  ],
],
'Hover' => [
  [
    'fields',
    'contents',
    'range',
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
'InitializeResult' => [
  [
    'fields',
    'capabilities',
  ],
],
'Location' => [
  [
    'fields',
    'uri',
    'range',
  ],
],
'MarkupContent' => [
  [
    'fields',
    'kind',
    'value',
  ],
],
'Position' => [
  [
    'fields',
    'line',
    'character',
  ],
],
'Range' => [
  [
    'fields',
    'start',
    'end',
  ],
],
'RenameOptions' => [
  [
    'fields',
    'prepareProvider',
  ],
],
'SaveOptions' => [
  [
    'fields',
    'includeText',
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
'TextDocumentIdentifier' => [
  [
    'fields',
    'uri',
  ],
],
'TextDocumentPositionParams' => [
  [
    'fields',
    'textDocument',
    'position',
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

   #==END_GENERATED

  );


1;
