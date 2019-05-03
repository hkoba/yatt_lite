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
# make_typedefs_from: InitializeParams InitializeResult TextDocumentPositionParams Location Hover MarkupContent ErrorCodes DidSaveTextDocumentParams DiagnosticSeverity PublishDiagnosticsParams TextDocumentSyncOptions
'ClientCapabilities' => [
  [
    'fields',
    'workspace',
    'textDocument',
    'experimental',
  ],
],
undef() => [
  [
    'constant',
    'CodeActionKind__QuickFix',
    'quickfix',
  ],
  [
    'constant',
    'CodeActionKind__Refactor',
    'refactor',
  ],
  [
    'constant',
    'CodeActionKind__RefactorExtract',
    'refactor.extract',
  ],
  [
    'constant',
    'CodeActionKind__RefactorInline',
    'refactor.inline',
  ],
  [
    'constant',
    'CodeActionKind__RefactorRewrite',
    'refactor.rewrite',
  ],
  [
    'constant',
    'CodeActionKind__Source',
    'source',
  ],
  [
    'constant',
    'CodeActionKind__SourceOrganizeImports',
    'source.organizeImports',
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
'Diagnostic' => [
  [
    'fields',
    'range',
    'severity',
    'code',
    'source',
    'message',
    'relatedInformation',
  ],
],
'DiagnosticRelatedInformation' => [
  [
    'fields',
    'location',
    'message',
  ],
],
undef() => [
  [
    'constant',
    'DiagnosticSeverity__Error',
    '1',
  ],
  [
    'constant',
    'DiagnosticSeverity__Warning',
    '2',
  ],
  [
    'constant',
    'DiagnosticSeverity__Information',
    '3',
  ],
  [
    'constant',
    'DiagnosticSeverity__Hint',
    '4',
  ],
],
'DidSaveTextDocumentParams' => [
  [
    'fields',
    'textDocument',
    'text',
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
undef() => [
  [
    'constant',
    'ErrorCodes__ParseError',
    '-32700',
  ],
  [
    'constant',
    'ErrorCodes__InvalidRequest',
    '-32600',
  ],
  [
    'constant',
    'ErrorCodes__MethodNotFound',
    '-32601',
  ],
  [
    'constant',
    'ErrorCodes__InvalidParams',
    '-32602',
  ],
  [
    'constant',
    'ErrorCodes__InternalError',
    '-32603',
  ],
  [
    'constant',
    'ErrorCodes__serverErrorStart',
    '-32099',
  ],
  [
    'constant',
    'ErrorCodes__serverErrorEnd',
    '-32000',
  ],
  [
    'constant',
    'ErrorCodes__ServerNotInitialized',
    '-32002',
  ],
  [
    'constant',
    'ErrorCodes__UnknownErrorCode',
    '-32001',
  ],
  [
    'constant',
    'ErrorCodes__RequestCancelled',
    '-32800',
  ],
  [
    'constant',
    'ErrorCodes__ContentModified',
    '-32801',
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
'PublishDiagnosticsParams' => [
  [
    'fields',
    'uri',
    'diagnostics',
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
'WorkspaceFolder' => [
  [
    'fields',
    'uri',
    'name',
  ],
],

   #==END_GENERATED

  );


1;
