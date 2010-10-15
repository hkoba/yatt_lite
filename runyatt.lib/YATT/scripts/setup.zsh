#!/bin/zsh

set -e
setopt err_return
function die { echo 1>&2 $*; return 1 }
autoload colors; colors

#========================================
# FindBin equivalent. (Depends on GNU readlink)
#========================================

# $checkout_dir/runyatt.lib/YATT/scripts
realbin=$(readlink -f $(cd $0:h && print $PWD))

# $checkout_dir/runyatt.lib
libdir=$realbin:h:h

# $checkout_dir/runyatt
driver_path=$libdir:r

# runyatt
driver_name=$driver_path:t

# $checkout_dir
codir=$libdir:h

#========================================
# Option parsing
#========================================

opt_spec=(
    x=o_xtrace
    n=o_dryrun
    y=o_yn

    --
    -myapp::
    -datadir::
    # -location
    # -document_root
    # -link_driver
    # -as:
)

zparseopts -D -A opts $opt_spec

[[ -n $o_xtrace ]] && set -x

if ! ((ARGC)); then
    die Usage: $0:t '[-n | -x]' DESTDIR
fi

destdir=$1; shift

if [[ $destdir == . ]]; then
    destdir=$PWD
elif [[ $destdir != /* ]]; then
    destdir=$PWD/$destdir
fi

#========================================
# utils.
#========================================
function x {
    print -- $bg[cyan]"$@"$bg[default]
    if [[ -z $o_dryrun ]]; then
	"$@"
    fi
}

function find_pat {
    perl -nle '
      BEGIN {$PAT = shift}
      if (/$PAT/) {print $1 and exit 0}
      elsif (eof) {print STDERR "Not found: $PAT\n"; exit 1}
' "$@"
}

function mkfile {
    zparseopts -D m:=mode
    echo $bg[cyan]mkfile $1 "$bg[default] as:"
    echo "$bg[blue]=============$bg[default]"
    if [[ -z $o_dryrun ]]; then
	tee $1
    else
	cat
    fi
    echo "$bg[blue]=============$bg[default]"
    if [[ -n $mode ]]; then
	x chmod -v $mode[-1] $1
    fi
}

function confirm {
    local yn confirm_msg=$1 dying_msg=$2
    if [[ -n $o_dryrun || -n $o_yn ]]; then
	true
    elif [[ -t 0 ]]; then
	read -q "yn?$confirm_msg (Y/n) " || die Canceled.
    else
	die $dying_msg, exiting...
    fi
}

#========================================
# Env checking.
#========================================

if ! perl -le 'exit 1 if $] < 5.010'; then
    die Perl 5.010 or higher is required for YATT::Lite!
fi

[[ -d /selinux && -e /selinux/access ]] && is_selinux=1 || is_selinux=0

#========================================
# apache config detection.
#========================================
# XXX: Should allow explicit option.

if [[ -r /etc/redhat-release ]]; then
    apache=/etc/httpd/conf/httpd.conf
    document_root=$(find_pat '^DocumentRoot\s+"([^"]*)"' $apache)
    APACHE_RUN_GROUP=$(find_pat '^Group\s+(\S+)' $apache)
elif [[ -r /etc/lsb-release ]] && source /etc/lsb-release; then
    case $DISTRIB_ID in
	(*Ubuntu*)

	apache=/etc/apache2/sites-available/default
	document_root=$(find_pat '^\s*DocumentRoot\s+"?([^"]*)"?' $apache)

	# for APACHE_RUN_GROUP
	source /etc/apache2/envvars
	if [[ -z $APACHE_RUN_GROUP ]]; then
	    die "Can't find APACHE_RUN_GROUP!"
	fi

	curgroups=($(id -Gn))
	if (($curgroups[(ri)$APACHE_RUN_GROUP] >= $#curgroups)); then
	    die User $USER is not a member of $APACHE_RUN_GROUP, stopped.
	fi
	;;
	(*)
	die "Unsupported distribution! Please modify $0 for $DISTRIB_ID"
	;;
    esac
else
    document_root=/var/www
    APACHE_RUN_GROUP=apache
fi

#========================================
# destdir verification/preparation and location detection.
#========================================

if ! [[ -e $destdir ]]; then
    confirm "Do you wan to create a destination directory '$destdir' now?" \
	"Can't find destination directory '$destdir'!"

    x mkdir -p $destdir
elif ! [[ -d $destdir ]]; then
    confirm "Destination '$destdir',
you specified, is not a directory.
Do you want to use its parent '${destdir:h}',
instead?" \
	"destdir '$destdir' is not a directory!"

    destdir=$destdir:h
fi

if [[ $destdir = $document_root/* ]]; then
    location=${destdir#$document_root}
elif [[ $destdir = $HOME/public_html/* ]]; then
    location=/~$USER${destdir#$HOME/public_html}
else
    die Can\'t extract URL from destdir=$destdir.
fi

#========================================
# Main.
#========================================
cgi_bin=$destdir/cgi-bin
cgi_loc=$location/cgi-bin

# Create library directory and link yatt in it.
x mkdir -p $cgi_bin/$driver_name.lib
mkfile $cgi_bin/$driver_name.lib/.htaccess <<EOF
deny from all
EOF
x ln -vnsf $driver_path.lib/YATT $cgi_bin/$driver_name.lib/YATT
mkfile $cgi_bin/.htaccess <<EOF
Options +ExecCGI
EOF
x ln -vnsf $driver_path.ytmpl $cgi_bin/

if (($is_selinux)); then
    # XXX: Only if user ownes original.
    # XXX: httpd_sys vs httpd_user
    # XXX: semanage fcontext -a -t $type
    x chcon -vR -t httpd_sys_content_t $driver_path.*(/) || true
fi

# Create custom DirHandler.
# XXX: only if missing.
if (($+opts[--myapp])); then
    # XXX: Must modify runyatt.cgi basens!
    myapp=${opts[--myapp][2,-1]:-MyApp}
    mkfile -m a+x $cgi_bin/$driver_name.lib/$myapp.pm <<EOF
#!/usr/bin/perl -w
package $myapp; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use FindBin;
use lib \$FindBin::RealBin;

use YATT::Lite::Web::DirHandler -as_base, qw(*YATT *CON Entity);

1;
EOF
fi

# Copy driver cgi and link fcgi.
x cp -vu $driver_path.cgi $cgi_bin/
if (($is_selinux)); then
    x chcon -v -t httpd_sys_script_exec_t $cgi_bin/$driver_name.cgi || true
fi
x ln -vnsf $driver_name.cgi $cgi_bin/$driver_name.fcgi

# Then activate it!
if [[ -r $destdir/dot.htaccess ]]; then
    x cp -v $destdir/dot.htaccess $destdir/.htaccess
    x sed -i -e "s|@DRIVER@|$cgi_loc/$driver_name.cgi|" $destdir/.htaccess
else
    mkfile $destdir/.htaccess <<EOF
Action x-yatt-handler $cgi_loc/$driver_name.cgi
# Action x-yatt-handler $cgi_loc/$driver_name.fcgi
AddHandler x-yatt-handler .yatt .ytmpl .ydo

Options -Indexes -Includes -ExecCGI
DirectoryIndex index.yatt index.html

<Files *.ytmpl>
deny from all
</Files>
EOF
fi

if [[ -d $destdir/data ]] || (($+opts[--datadir])); then
    datadir=${opts[--datadir][2,-1]:-$destdir/data}
    if [[ -d $datadir ]]; then
	x chmod -v 2775 $datadir
	x chgrp -v $APACHE_RUN_GROUP $datadir
    else
	x install -m 2775 -g $APACHE_RUN_GROUP -d $datadir
    fi
    mkfile $datadir/.htaccess <<<"deny from all"
    if (($is_selinux)); then
	x chcon -v -t httpd_sys_script_rw_t $datadir
    fi
fi

if [[ -z $o_dryrun ]]; then
    echo $bg[green]OK$bg[default]: URL=http://localhost$location/
fi
