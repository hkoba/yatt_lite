#!/bin/zsh

set -e
setopt err_return
function die { echo 1>&2 $*; return 1 }

setopt extendedglob

# XXX: Only work for current directory.

files=(
    cgi-bin/runyatt.*(@N)
    cgi-bin/runyatt.cgi
    cgi-bin/runyatt.lib/YATT(@N)
    cgi-bin/runyatt.lib/.htaccess
    cgi-bin/.htaccess
    .htaccess
)

rm -fv $files

myapp=(
    cgi-bin/runyatt.lib/*.pm(.N)
)

if ! (($#myapp)); then
    rm -vrf cgi-bin
fi
