package YATT::Lite::Partial::Gettext; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw/all/;
use YATT::Lite::Partial
  (fields => [qw/locale_cache/], requires => [qw/error/]);

use YATT::Lite::Util qw/ckeval/;

#========================================
# Locale support.
#========================================

use YATT::Lite::Util::Enum (_E_ => [qw/MTIME DICT FORMULA NPLURALS HEADER/]);

sub configure_locale {
  (my MY $self, my $spec) = @_;

  require Locale::PO;

  if (ref $spec eq 'ARRAY') {
    my ($type, @args) = @$spec;
    my $sub = $self->can("configure_locale_$type")
      or $self->error("Unknown locale spec: %s", $type);
    $sub->($self, @args);
  } else {
    die "NIMPL";
  }
}

# XXX: .htyatt.ja.po ¤Ï ? ÃÙ±ä load ¤Ï¡© refresh ¤Ï?
# sub configure_locale_dir {
#   (my MY $self, my $dir) = @_;
# 
#   foreach my $fn (glob("$dir/*.po")) {
#     my ($lang) =~ m{/(\w+)\.po$}
#       or next;
#     my $hash = $self->{locale_cache}{$lang} = {};
#     foreach my $loc (@{Locale::PO->load_file_asarray($fn)}) {
#       my $id = $loc->dequote($loc->msgid);
#       $hash->{$id} = $loc;
#     }
#   }
# }

sub configure_locale_data {
  (my MY $self, my $value) = @_;
  my $cache = $self->{locale_cache} ||= {};
  foreach my $lang (keys %$value) {
    my $entry = [];
    $entry->[_E_DICT] = my $locale = $value->{$lang};
    if (my $header = $locale->{''}) {
      my $xhf = YATT::Lite::XHF::parse_xhf
	($header->dequote($header->msgstr));
      my ($sub, $nplurals);
      if (my $form = $xhf->{'Plural-Forms'}) {
	if (($nplurals, my $formula) = $form =~ m{^\s*nplurals\s*=\s*(\d+)\s*;
						  \s*plural\s*=\s*([^;]+)}x) {
	  $formula =~ s/\bn\b/\$n/g;
	  $sub = ckeval(sprintf q|sub {my ($n) = @_; %s}|, $formula);
	}
      } else {
	$sub = \&lang_plural_formula_en;
	$nplurals = 2;
      }
      @{$entry}[_E_FORMULA, _E_NPLURALS, _E_HEADER] = ($sub, $nplurals, $xhf);
    }
    $cache->{$lang} = $entry;
  }
}

sub _lang_dequote {
  shift;
  my $string = shift;
  $string =~ s/^"(.*)"/$1/s; # XXX: Locale::PO::dequote is not enough.
  $string =~ s/\\"/"/g;
  return $string;
}

sub lang_plural_formula_en { my ($n) = @_; $n != 1 }

sub lang_gettext {
  (my MY $self, my ($lang, $msgid)) = @_;
  my $entry = $self->lang_getmsg($lang, $msgid)
    or return $msgid;
  $entry->dequote($entry->msgstr);
}

sub lang_ngettext {
  (my MY $self, my ($lang, $msgid, $msg_plural, $num)) = @_;
  if (my ($locale, $entry) = $self->lang_getmsg($lang, $msgid)) {
    my $ix = $locale->[_E_FORMULA]->($num);
    my $hash = $entry->msgstr_n;
    if (defined (my $hit = $hash->{$ix})) {
      return $entry->dequote($hit);
    }
  }
  return ($msgid, $msg_plural)[lang_plural_formula_en($num)];
}

sub lang_getmsg {
  (my MY $self, my ($lang, $msgid)) = @_;
  my ($locale, $msg);
  if (defined $msgid and defined $lang
      and $locale = $self->{locale_cache}{$lang}
      and $msg = $locale->[_E_DICT]{$msgid}) {
    wantarray ? ($locale, $msg) : $msg;
  } else {
    return;
  }
}

1;
