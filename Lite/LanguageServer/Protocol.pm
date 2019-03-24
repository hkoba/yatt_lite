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
'CompletionOptions' => [
  [
    'fields',
    'resolveProvider',
    'triggerCharacters',
  ],
],
'ExecuteCommandOptions' => [
  [
    'fields',
    'commands',
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
'RenameOptions' => [
  [
    'fields',
    'prepareProvider',
  ],
],
'DocumentOnTypeFormattingOptions' => [
  [
    'fields',
    'firstTriggerCharacter',
    'moreTriggerCharacter',
  ],
],
'SignatureHelpOptions' => [
  [
    'fields',
    'triggerCharacters',
  ],
],
'CodeActionOptions' => [
  [
    'fields',
    'codeActionKinds',
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
'DocumentLinkOptions' => [
  [
    'fields',
    'resolveProvider',
  ],
],
'InitializeResult' => [
  [
    'fields',
    'capabilities',
  ],
],
'SaveOptions' => [
  [
    'fields',
    'includeText',
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

   #==END_GENERATED

  );


1;
