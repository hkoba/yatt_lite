#!/bin/zsh

set -e
setopt err_return
function die { echo 1>&2 $*; return 1 }

autoload colors
colors

setopt extendedglob

zparseopts -D y=o_yn n=o_dryrun || exit 1

o_verbose=()
(($#o_yn)) || o_verbose=(-v)

function confirm {
    local yn confirm_msg=$1 dying_msg=$2
    if [[ -n $o_dryrun || -n $o_yn ]]; then
	true
    elif [[ -t 0 ]]; then
	read -q "yn?$confirm_msg (Y/n) " || die " ..canceled."
	print
    else
	die $dying_msg, exiting...
    fi
}

if ((ARGC)); then
    cd $1
fi

# XXX: How about runyatt.psgi?
files=(
    cgi-bin/runyatt.*(@N)
    cgi-bin/runyatt.(cgi|fcgi|psgi)(N)
    cgi-bin/runyatt.lib/YATT(@N)
    cgi-bin/runyatt.lib/.htaccess(N)
    cgi-bin/.htaccess(N)
    .htaccess(N)
)

myapp=(
    cgi-bin/runyatt.lib/*.pm(.N)
)

(($#o_yn)) || {
    print Deleting following files:
    print -c "  $PWD"/$^files
    if ! (($#myapp)); then
	print -c "  $PWD"/cgi-bin
    fi
}

confirm "Are you sure to $bg[red]delete$bg[default] these?"

rm -f $o_verbose $files

if ! (($#myapp)); then
    rm -rf $o_verbose cgi-bin
fi

print Now cleaned-up: $PWD
