#!/bin/zsh

# This is a test driver for YATT::Lite. Just run this without argument.
# This will apply ``prove'' to all *.t.
# Also, if you specify '-C' flag, Coverage will be gathered.

set -e
setopt extendedglob

# chdir to $DIST_ROOT
bindir=$(cd $0:h; print $PWD)
cd $0:h:h:h

zparseopts -D -A opts C=o_cover || true

# If no **/*.t is specified:
if [[ -z $argv[(r)(*/)#*.t] ]]; then
    # To make relative path invocation happier.
    argv=($0:h:h:t/t/*.t(N))
    if [[ -d samples ]]; then
	argv+=(samples/**/t/*.t(*N,@N))
    fi
fi

if (($+PERL)) && [[ -d $PERL:h/lib ]]; then
    export PERL5LIB=$PERL:h/lib:$PERL5LIB
fi

if [[ -n $o_cover ]]; then
    echo "[[Coverage mode]]"
    cover_db=$bindir/cover_db
    charset=utf-8

    typeset -T HARNESS_PERL_SWITCHES harness ' '
    export HARNESS_PERL_SWITCHES
    harness+=(-MDevel::Cover=-db,$cover_db)
fi

${PERL:-perl} =prove $argv || true

: ${docroot:=/var/www/html}
if [[ -n $o_cover ]] && [[ -d $cover_db ]]; then
    # ``t/cover'' is modified to accpet charset option.
    $bindir/cover -charset $charset -ignore_re '\.t$' $cover_db

    chmod a+rx $cover_db $cover_db/**/*(/N)
    cat <<EOF > $cover_db/.htaccess
allow from localhost
DirectoryIndex coverage.html
AddHandler default-handler .html
AddType "text/html; charset=$charset" .html
EOF

    print Coverage URL: http://localhost${cover_db#$docroot}/
fi

