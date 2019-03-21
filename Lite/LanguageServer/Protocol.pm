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

   CancelParams => [[fields => qw/id/]],
   Position => [[fields => qw/line character/]],
   Range => [[fields => qw/start end/]],
   Location => [[fields => qw/uri range/]],
   LocationLink => [[fields => qw/originSectionRange targetUri targetRange targetSelectionRange/]],

   SignatureHelp => [[fields => qw/signatures activeSignature activeParameter/]],
   SignatureInformation => [[fields => qw/label documentation parameters/]],
   ParameterInformation => [[fields => qw/label documentation/]],
  );


1;
