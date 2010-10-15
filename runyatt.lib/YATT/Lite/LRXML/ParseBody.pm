package YATT::Lite::LRXML::ParseBody; # dummy package, for lint.
use strict;
use warnings FATAL => qw(all);

package YATT::Lite::LRXML; use YATT::Lite::LRXML;

sub _parse_body {
  (my MY $self, my Widget $widget, my ($sink, $close, $parent, $par_ln)) = @_;
  # $sink は最初、外側の $body 配列。
  # <:option /> が出現した所から先は、 その option element の body が新しい $sink になる

  # 非空白文字が出現したか。 <:opt>HEAD</:opt> と BODY の間に
  my $has_nonspace;
  while (s{^(.*?)$$self{re_body}}{}xs or my $retry = $self->_get_chunk($sink)) {
    next if $retry;
    $self->{endln} += numLines($&);
    if ($self->add_posinfo(length($1), 1)) {
      push @$sink, splitline($1);
      $$par_ln = $self->{startln}
	if nonspace($1) and not $has_nonspace++ and $parent;
      $self->{startln} += numLines($1);
    }
    $self->{curpos} += length($&) - length($1);
    $self->_verify_token($self->{curpos}, $_) if $self->{cf_debug};
    if ($+{entity} or $+{special}) {
      # &yatt(?=:) までマッチしてる。
      # XXX: space 許容モードも足すか。
      push @$sink, my $node = $self->mkentity
	($self->{startpos}, undef, $self->{endln});
      # ; まで
      $node->[NODE_END] = $self->{curpos};
      $self->_verify_token($self->{curpos}, $_) if $self->{cf_debug};
      $self->add_lineinfo($sink);
      $$par_ln = $self->{startln}
	if nonspace($1) and not $has_nonspace++ and $parent;
    } elsif (my $path = $+{elem}) {
      if ($+{clo}) {
	$parent->[NODE_BODY_END] = $self->{startpos};
	if ($self->{template}->node_body_source($parent) =~ /(\r?\n)\Z/) {
	  $parent->[NODE_BODY_END] -= length $1;
	}
	$self->verify_tag($path, $close);
	if (@$sink and not ref $sink->[-1] and $sink->[-1] =~ s/(\r?\n)\Z//) {
	  push @$sink, "\n";
	}
	# $self->add_lineinfo($sink);
	return @$sink;
      }
      # /? > まで、その後、not ee なら clo まで。
      my $is_opt = $+{opt};
      my $body = [];
      my $elem = [$is_opt ? TYPE_ATT_NESTED : TYPE_ELEMENT
		  , $self->{startpos}, undef, $self->{endln}
		  , [split /:/, $path]
		 , $is_opt ? $body : [TYPE_ATTRIBUTE, undef, undef, undef
				      , body => $body]];
      # $is_opt の時に、更に body を attribute として保存するのは冗長だし、後の処理も手間なので
      if (my @atts = $self->parse_attlist($_)) {
	$elem->[NODE_ATTLIST] = \@atts;
      }
      # タグの直後の改行は、独立したトークンにしておく
      unless (s{^(?<empty_elem>/)? >(\r?\n)?}{}xs) {
	die $self->synerror(q{Missing tagclose: %s}, $_);
      }
      $self->{curpos} += 1 + ($1 ? length($1) : 0);
      my $bodyStartRef = \ $elem->[NODE_BODY][NODE_LNO] unless $is_opt;
      $elem->[NODE_END] = $self->{curpos};
      $self->{curpos} += length $2 if $2;
      $elem->[NODE_BODY_BEGIN] = $self->{curpos};
      $self->_verify_token($self->{curpos}, $_) if $self->{cf_debug};

      if ($is_opt and not $+{empty_elem}) {
	drop_leading_ws($sink);
      }

      # <:opt/> の時は $parent->[foot] へ、そうでなければ現在の $sink へ。
      push @{$is_opt && $+{empty_elem}
	       ? $parent->[NODE_AELEM_FOOT] ||= []
		 : $sink}, $elem;

      # <:opt> の時は, $parent->[head] にも加える
      push @{$parent->[NODE_AELEM_HEAD] ||= []}, $elem
	if $is_opt && !$+{empty_elem};

      # <TAG>\n タグ直後の改行について。
      # <foo />\n だけは, 現在の $sink へ、それ以外は、今作る $elem の $body へ改行を足す
      $self->{endln}++, push @{!$is_opt && $+{empty_elem} ? $sink : $body}, "\n"
	if $2;

      unless ($is_opt) {
	$$par_ln = $self->{startln} if not $has_nonspace++ and $parent;
      } elsif (not $+{empty_elem}) {
	# XXX: もし $is_opt かつ not ee だったら、
	# $sink (親の $body) が空かどうかを調べる必要が有る。
#	die $self->synerror(q{element option '%s' must precede body!}, $path)
#	  if $has_nonspace;
      }
      if (not $+{empty_elem}) {
	# call <yatt:call> ...  or complex option <:yatt:opt>
	# expects </yatt:call> or </:yatt:opt>
	my $startln = $self->{startln};
	$self->_parse_body($widget, $body
			   , $+{empty_elem} ? $close : $path
			   , $elem, $bodyStartRef);
	$$bodyStartRef ||= $startln;
      } elsif ($is_opt) {
	# ee style option.
	# <:yatt:foo/>bar 出現後は、以後の要素を att に加える。
	$sink = $body;
      } else {
      }				# simple call.
      $self->_verify_token($self->{curpos}, $_) if $self->{cf_debug};
      $self->add_lineinfo($sink);
      # @$body が空なら、予め開放しておく。
      undef $elem->[NODE_BODY] unless @$body;
    } elsif ($path = $+{pi}) {
      $$par_ln = $self->{startln} if not $has_nonspace++ and $parent;
      # ?> まで
      unless (s{^(.*?)\?>(\r?\n)?}{}s) {
	die $self->synerror(q{Unbalanced pi});
      }
      my $end = $self->{curpos} += 2 + length($1);
      my $nl = "\n" if $2;
      # XXX: parse_text の前なので、本当は良くない
      $self->{curpos} += length $2 if $2;
      push @$sink, [TYPE_PI, $self->{startpos}, $end
		    , $self->{endln}
		    , [split /:/, $path]
		    , lexpand($self->_parse_text_entities($1))];
      if ($nl) {
	push @$sink, $nl;
	$self->{startln} = ++$self->{endln};
      }
      $self->add_lineinfo($sink);
    } else {
      die join("", "Can't parse: ", nonmatched($_));
    }
  } continue {
    $self->{startln} = $self->{endln};
    $self->{startpos} = $self->{curpos};
    $self->_verify_token($self->{startpos}, $_) if $self->{cf_debug};
  }
}

use YATT::Lite::Breakpoint qw(break_load_parsebody);
break_load_parsebody();

1;
