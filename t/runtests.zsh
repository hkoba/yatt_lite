#!/bin/zsh

# This is a test driver for YATT::Lite. Just run this without argument.
# This will apply ``prove'' to all *.t.
# Also, if you specify '-C' flag, Coverage will be gathered.

set -e
setopt extendedglob

# chdir to $DIST_ROOT
bindir=$(cd $0:h; print $PWD)
if [[ $bindir != */YATT/t ]]; then
    cat 1>&2 <<EOF; exit 1
YATT installation path problem!
To use this t/runtests.zsh, your installation should end with 'YATT'.
(You can achieve it like this: git clone ...  lib/YATT)
EOF

fi

libdir=$bindir:h:h
distdir=$bindir:h
cd $distdir

optspec=(
    C=o_cover
    T=o_taint
    'l+:=o_lib'
    -nosamples
    -samples
    -brew::
)

zparseopts -D -A opts $optspec || true

if (($+opts[--samples])); then
    # Test samples only.
    argv=(samples/**/t/*.t(*N,@N))

elif [[ -z $argv[(r)(*/)#*.t] ]]; then
    # If no **/*.t is specified:
    # To make relative path invocation happier.
    argv=(t/**/*.t(N))
    if ((! $+opts[--nosamples])) && [[ -d samples ]]; then
	argv+=(samples/**/t/*.t(*N,@N))
    fi
fi

if (($+opts[--brew])); then
    PERL=${opts[--brew][2,-1]:-~/perl5/perlbrew/bin/perl}
fi

if (($+PERL)); then
    if [[ -d $PERL:h/lib ]]; then
	# For barely built perl.
	export PERL5LIB=$PERL:h/lib:$PERL5LIB
    fi
fi

typeset -T HARNESS_PERL_SWITCHES harness ' '
export HARNESS_PERL_SWITCHES

if [[ -n $o_taint ]]; then
    echo "[with taint check]"
    harness+=($o_taint)
else
    echo "[normal mode (no taint check)]"
fi

if [[ -n $o_cover ]]; then
    echo "[[Coverage mode]]"
    cover_db=$bindir/cover_db
    charset=utf-8

    ignore=(
	-ignore_re '^/usr/local/'
	-ignore_re '\.(?:t|yatt|ytmpl|ydo|htyattrc\.pl|psgi)$'
	-ignore_re '^My[A-Z]'
	-ignore_re '/t_'
	-ignore_re '^f\d+$'
    )
    for d in ${(s/:/)PERL5LIB}; do
	ignore+=(-ignore_re "^$d")
    done

    harness+=(-MDevel::Cover=-db,$cover_db,${(j/,/)ignore})

    harness+=(-I$libdir)

    if (($#o_lib)); then
	for o val in $o_lib; do
	    harness+=(-I$val)
	done
    fi
fi

if [[ -n $HARNESS_PERL_SWITCHES ]]; then
    print -R HARNESS_PERL_SWITCHES=$HARNESS_PERL_SWITCHES
fi
if [[ -n $o_taint ]]; then
    ${PERL:-perl} -MTest::Harness -e 'runtests(@ARGV)' $argv || true
else
    ${PERL:-perl} =prove $o_lib $argv || true
fi

: ${docroot:=/var/www/html}
if [[ -n $o_cover ]] && [[ -d $cover_db ]]; then
    # ``t/cover'' is modified to accpet charset option.
    $bindir/cover -charset $charset $ignore $cover_db

    chmod a+rx $cover_db $cover_db/**/*(/N)
    cat <<EOF > $cover_db/.htaccess
allow from localhost
DirectoryIndex coverage.html
AddHandler default-handler .html
AddType "text/html; charset=$charset" .html
EOF

    print Coverage URL: http://localhost${cover_db#$docroot}/
fi

