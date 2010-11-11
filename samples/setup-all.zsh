#!/bin/zsh

# set -e
cd $0:h || exit 1

zparseopts -D -A opts p=o_save_password -testdb:: -testuser:: || exit 1

if (($+o_save_password)); then
    testdb=${opts[--testdb][2,-1]:-test}
    testuser=${opts[--testuser][2,-1]:-${USER:-test}}
    print "(testdb=$testdb, testuser=$testuser)"
    print -n "Enter DB password for samples "
    read -s pass
    cat > .htdbpass <<EOF
dbname: $testdb
dbuser: $testuser
dbpass: $pass
EOF

    print "DB password is saved in $PWD/.htdbpass"
fi

for f in **/t; do
  ../runyatt.lib/YATT/scripts/setup.zsh $f:h
done
