package YATT::Lite::Test::XHFTest;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use parent qw(YATT::Lite::Object);
use YATT::Lite::MFields qw/_tests _numtests _yatt _global _file_list _file_dict
	      filename ext parser encoding
	      lang
	      _prev_item _builder/;
use Exporter 'import';
sub MY () {__PACKAGE__}
use YATT::Lite::Util qw(default dict_sort lexpand);
sub default_ext {'yatt'}

# Language specific overrides: FIELD[lang] and ONLY. See pod below.
sub default_lang {'perl'}
sub known_langs {qw(perl js go)}
sub lang_group_fields {qw(OUT ERROR ERROR_BODY)}
sub lang_item_fields {
  (shift->lang_group_fields, qw(SKIP TODO PERL_MINVER REQUIRE));
}
sub lang_header_fields {qw(YATT_CONFIG YATT_RC)}

# Fields which can appear multiple times. Their values are always arrays.
sub multi_item_fields {qw(TAG REQUIRE)}
sub multi_header_fields {()}
our @EXPORT_OK = qw(Item);

use Encode;

{
  sub Item () {'YATT::Lite::Test::XHFTest::Item'}
  package YATT::Lite::Test::XHFTest::Item;
  use parent qw(YATT::Lite::Object);
  use YATT::Lite::Util qw(lexpand);
  use YATT::Lite::MFields qw/global
		parser

		_num
		_realfile

		FILE
		TITLE
		BREAK
		SKIP
		TODO
		PERL_MINVER

		WIDGET
		RANDOM
		IN
		PARAM
		OUT
		ERROR
                ERROR_BODY

		REQUIRE
		ONLY
		_only_skip

		TAG
                CON_CLASS
	      /;

  sub is_runnable { shift->ntests }
  sub ntests {
    my __PACKAGE__ $item = shift;
    if ($item->{OUT}) {
      2;
    } elsif ($item->{ERROR}) {
      1;
    } else {
      0;
    }
  }
  sub test_require {
    my ($self, $reqlist) = @_;
    grep {not eval qq{require $_}} lexpand($reqlist);
  }

}

require YATT::Lite::XHF;
sub Parser () {'YATT::Lite::XHF'}

sub list_files {
  my $pack = shift;
  map {
    ! -d $_ ? $_ : dict_sort <$_/*.xhf>;
  } @_;
}

sub after_new {
  my MY $self = shift;
  $self->{_numtests} = 0;
  $self->{_tests} = [];
  $self->{ext} //= $self->default_ext;
  $self->{lang} //= $self->default_lang;
  $self;
}
sub load {
  my ($pack, %opts) = @_;
  my $lang = delete $opts{lang};
  my Parser $parser = $pack->Parser->new(%opts);
  my MY $self = $pack->new($parser->cf_delegate(qw(filename))
			   , parser => $parser, lang => $lang);
  $self->check_lang($self->{lang}, "lang option");
  if (my $global = $self->read_resolved(header => skip_comment => 0)) {
    $self->configure(@$global);
    $parser->configure($self->cf_delegate_defined(qw(encoding)));
  }
  while (my $config = $self->read_resolved('item')) {
    my Item $item = $self->Item->new(@$config);
    if (defined $item->{ONLY}
        and not grep {$_ eq $self->{lang}} split " ", $item->{ONLY}) {
      $item->{_only_skip} = "ONLY: $item->{ONLY}";
    }
    $self->add_item($item);
  }
  $self;
}

# Reads one paragraph and resolves FIELD[lang] and ONLY for $self->{lang}.
# Returns undef at the end of input.
sub read_resolved {
  (my MY $self, my ($kind, @opts)) = @_;
  my Parser $parser = $self->{parser};
  my @tokens = $parser->cf_let(\@opts, 'tokenize')
    or return;
  my @config = $parser->organize(@tokens);

  # Line numbers of top level fields, to report errors.
  my ($depth, @lineno) = (0);
  foreach my $tok (@tokens) {
    my ($name, $sigil, undef, $lineno) = @$tok;
    if (not defined $name) {
      $depth--;
      next;
    }
    if (not $depth) {
      die "XHF test field without name "
        . $parser->fileinfo_lineno($lineno) . "\n" if $name eq '';
      push @lineno, $lineno;
    }
    $depth++ if $sigil eq '[' or $sigil eq '{';
  }
  @lineno * 2 == @config
    or die "XHF test paragraph is not a list of fields "
    . $parser->fileinfo_lineno($tokens[0][3]) . "\n";

  [$self->resolve_lang_fields
   ($kind, map {[$config[2*$_], $config[2*$_+1], $lineno[$_]]} 0 .. $#lineno)];
}

sub check_lang {
  (my MY $self, my ($lang, $where)) = @_;
  grep {$lang eq $_} $self->known_langs
    or die "Unknown language '$lang' in $where"
    . " (known languages: @{[$self->known_langs]})\n";
  $lang;
}

# $kind is 'header' or 'item'. Each field is [$name, $value, $lineno].
# Returns key value list resolved for $self->{lang}.
sub resolve_lang_fields {
  (my MY $self, my ($kind, @fields)) = @_;
  my Parser $parser = $self->{parser};
  my $lang = $self->{lang};
  my %allowed = map {$_ => 1}
    $kind eq 'header' ? $self->lang_header_fields : $self->lang_item_fields;
  my %group = map {$_ => 1} $self->lang_group_fields;

  my %multi = map {$_ => 1}
    $kind eq 'header' ? $self->multi_header_fields : $self->multi_item_fields;

  # XHF reader returns duplicate keys as they are (like mail headers).
  # Here, they are multiple values only for fields declared so.
  # Others are errors, since they are mostly missing paragraph separators.
  my (%seen, @plain, @override, $group_overridden);
  my $add = sub {
    my ($list, $key, $base, $value, $at) = @_;
    if (my $found = $seen{$key}) {
      $multi{$base}
        or die "Duplicate XHF test field '$key' $at\n";
      push @{$found->[1]}, lexpand($value);
    } else {
      push @$list, $seen{$key}
        = [$base, $multi{$base} ? [lexpand($value)] : $value];
    }
  };
  foreach my $field (@fields) {
    my ($name, $value, $lineno) = @$field;
    my $at = $parser->fileinfo_lineno($lineno);
    if ($name =~ m{^([^\[\]]*)\[}) {
      my $base = $1;
      my ($sub) = $name =~ m{^[^\[\]]+\[([^\[\]]*)\]\z}
        or die "Invalid subscript in XHF test field '$name' $at\n";
      $self->check_lang($sub, "XHF test field '$name' $at");
      $allowed{$base}
        or die "XHF test $kind field '$base' can't have language subscript:"
        . " '$name' $at\n";
      # Duplicates are checked for other languages too.
      $add->($sub eq $lang ? \@override : [], $name, $base, $value, $at);
      $group_overridden = 1 if $sub eq $lang and $group{$base};
    } else {
      if ($kind eq 'item' and $name eq 'ONLY') {
        my @only = split " ", $value // '';
        @only or die "Empty ONLY in XHF test $at\n";
        $self->check_lang($_, "ONLY $at") for @only;
        $value = "@only";
      }
      $add->(\@plain, $name, $name, $value, $at);
    }
  }

  # Expectations (OUT, ERROR, ERROR_BODY) are replaced as a group.
  my %overridden = map {$_->[0] => 1} @override;
  map {@$_} (grep {
    not $overridden{$_->[0]}
      and not ($group_overridden and $group{$_->[0]})
  } @plain), @override;
}

sub convert_enc_array {
  my ($self, $enc, $array) = @_;
  foreach (@$array) {
    unless (ref $_) {
      $_ = decode($enc, $_)
    } elsif (ref $_ eq 'ARRAY') {
      $_ = $self->convert_enc_array($enc, $_);
    } else {
      # nop.
    }
  }
  $array;
}

sub ntests {
  my MY $self = shift; $self->{_numtests}
}
sub add_item {
  (my MY $self, my Item $item) = @_;
  if ($item->{global}) {
    $self->{_global} = $item->{global};
    next;
  }
  push @{$self->{_tests}}, $self->fixup_item($item);
  $self->{_numtests} += $item->ntests;
}

sub fixup_item {
  (my MY $self, my Item $test) = @_;
  my Item $prev = $self->{_prev_item};
  $test->{FILE} ||= do {
    if ($prev && $prev->{FILE} =~ m{%d}) {
      $prev->{FILE}
    } else {
      "f%d.$self->{ext}"
    }
  };

  $test->{_realfile} = do {
    if ($test->{IN}) {
      no if $] >= 5.021002, warnings => qw/redundant/;
      sprintf($test->{FILE}, 1+@{$self->{_file_list} //= []})
    } else {
      $prev->{_realfile}
    }
  };

  $test->{WIDGET} ||= do {
    my $widget = $test->{_realfile};
    $widget =~ s{\.\w+$}{};
    $widget =~ s{/}{:}g;
    $widget;
  };

  if ($test->{IN}) {
    if (my $conflict = $self->{_file_dict}{$test->{_realfile}}) {
      die "FILE name confliction in test $test";
    }
    $self->{_file_dict}{$test->{_realfile}} = $test;
    push @{$self->{_file_list}}, $test->{_realfile};
  }

  if ($test->{OUT} || $test->{ERROR}) {
    $test->{WIDGET} ||= $prev && $prev->{WIDGET};
    if (not $test->{TITLE} and $prev) {
      $test->{_num} = default($prev->{_num}, 0) + 1;
      $test->{TITLE} = $prev->{TITLE};
    }
    $self->{_prev_item} = $test;
  }

  $test;
}

sub as_vfs_data {
  my MY $self = shift;
  my (%result);
  # 記述の順番どおりに作成
  foreach my $fn (@{$self->{_file_list}}) {
    my Item $item = $self->{_file_dict}{$fn};
    my @path = split m|/|, $fn;
    my $path_cursor = path_cursor(\%result, \@path);
    $path[0] =~ s|\.(\w+)$||
      or die "Can't handle filename as vfs key: $fn";
    my $ext = $1;
    if (my $sub = $self->can("convert_$ext")) {
      $sub->($self, $path_cursor, $item)
    } else {
      # XXX: 既に配列になってると困るよね。 rc 系を後回しにすれば大丈夫?
      unless (defined $item->{IN}) {
	die "undef IN"
      }
      $path_cursor->[0]{$path[0]} = $item->{IN};
    }
  }
  \%result;
}

sub path_cursor {
  my ($top, $path) = @_;
  # path を一個残して、vivify する。
  # そこにいたる経路を cursor として返す。
  my $cursor = [$top];
  while (@$path > 1) {
    my $nm = shift @$path;
    $cursor = [$cursor->[0]{$nm} ||= {}, $cursor];
  }
  $cursor;
}

1;

__END__

=head1 NAME

YATT::Lite::Test::XHFTest - Loader of XHF based template tests (t/xhf/*/*.xhf)

=head1 DESCRIPTION

A test file is a series of XHF paragraphs. The first paragraph (header) is
the configuration of the file (C<encoding>, C<YATT_CONFIG>, C<YATT_RC>...).
Each of the rest is a test item, which has fields like
C<TITLE>, C<FILE>, C<IN>, C<PARAM>, C<OUT>, C<ERROR>, C<ERROR_BODY>,
C<SKIP>, C<TODO>, C<PERL_MINVER> and C<REQUIRE>.

These files are shared as the spec tests between implementations of yatt
in other languages. Following rules are for that.

=head2 Languages

Known languages are C<perl>, C<js> and C<go> (See C<known_langs>).
The language of the test runner is given by C<< lang => $lang >> option
of C<load> (default is C<default_lang>, C<perl>).

=head2 C<FIELD[lang]> -- language specific override

A field without subscript is the default for all languages.
C<FIELD[lang]> overrides C<FIELD> only when the runner is for C<lang>.
(XHF parser itself has no knowledge about this. C<OUT[js]> is just a name.)

  TITLE: valueless bool arg
  IN:
   <yatt:foo x/>
   <!yatt:widget foo x=bool>
   &yatt:x;
  OUT:
   1
  OUT[js]:
   true

=over 4

=item *

Subscript is allowed for
C<OUT>, C<ERROR>, C<ERROR_BODY>, C<SKIP>, C<TODO>, C<PERL_MINVER>
and C<REQUIRE> in test items, C<YATT_CONFIG> and C<YATT_RC> in the header.
Others (C<IN>, C<PARAM>, C<FILE>, C<TITLE>, C<WIDGET>...) are errors.
If inputs differ, they are different tests. Write another item with C<ONLY>.

=item *

Expectations (C<OUT>, C<ERROR>, C<ERROR_BODY>) are resolved B<as a group>.
If an item has any of them with C<[lang]>, all of them without subscript
are ignored for that language. So an item with C<OUT:> and C<ERROR[js]:> is
a test of OUT in perl and a test of ERROR in js.

=item *

Unknown language and subscript on other fields
are errors with file name and line number.

=back

=head2 Duplicate fields

XHF itself allows duplicate keys (like mail headers), and XHF reader returns
them as they are. In test files, they mean multiple values only for
C<TAG> and C<REQUIRE> (See C<multi_item_fields>).
Values of these fields are always arrays, and C<REQUIRE[lang]> replaces
whole values of C<REQUIRE>.

  TAG: entity
  TAG: var

Other duplicate fields (including subscripted ones) are errors
with file name and line number,
since they are mostly caused by broken paragraph separators.

=head2 C<ONLY: lang...>

Space separated list of languages. The item is skipped
(with C<ONLY> in the reason) by the runners of other languages.
The file given by C<IN> of the item is still defined, so that
numbering of files (C<f%d.yatt>) is same in all languages.

=head2 C<SKIP[lang]> and C<TODO[lang]>

Same as C<SKIP> and C<TODO> after the resolution.
C<SKIP> is for the feature which is out of the scope of the language.
C<TODO> is for the feature which is not yet implemented (failure is expected).

=cut
