#!/usr/bin/env sh

# Uncomment for debugging
#set +x

today=$(date +%Y%m%d)
to="sysops@nexylan.com"
from="binpkg@nexylan.com"
logdir="logs"

if [ ! -d "$logdir" ] ; then
    mkdir "$logdir"
fi

update_repo()
{
    eix-sync >> "$logdir"/update_repo-${today}.log 2>&1
}

cleaning_pkg()
{
    eclean -d distfiles && eclean -d packages
} >> "$logdir"/eclean-${today}.log 2>&1

read_news()
{
    eselect news read new >> "$logdir"/read_news-${today}.log 2>&1
}

update_packages()
{
    emerge --update --deep --with-bdeps=y --newuse --verbose world \
    >> "$logdir"/update_packages-${today}.log 2>&1
}

check_if_new_pkg()
{
    sed -n 's/^\[ebuild.\+U.\+\].\(.*\)\(\[.*\]\).USE=.*/Update: \1 previous: \2/p' "$logdir"/update_packages-${today}.log >> "$logdir"/check_if_new_pkg-${today}.log 2>&1
}

build_pkg()
{
    pkgs=$(ls /var/db/pkg/)
    for pkg in "$pkgs"
        do
	    if [ ! "$pkg" == "virtual" ] || [ ! "$pkg" == "dev-lang"] ; then
	        quickpkg --include-unmodified-config y "$pkg/*"
	    fi
	done
}

send()
{
    mail -a "From: $from" -s "News from BinPKG" "$to"
}

update_repo &&
cleaning_pkg &&
read_news &&
update_packages &&
check_if_new_pkg || exit 1

news=$(cat "$logdir"/read_news-${today}.log)
pkg=$(cat "$logdir"/check_if_new_pkg-${today}.log)
clean=$(cat "$logdir"/eclean-${today}.log)

if [ $(wc -l < "$logdir"/check_if_new_pkg-${today}.log) -gt 0 ] ; then
    cat <<EOF |
== News ==

$news

== Packages ==

$pkg

== Cleaning some packages ==

$clean

Love, BinPKG.

EOF
    send
    build_pkg
    exit 0
else
    echo -e "$(date): No update available" >> "$logdir"/binpkg.log 2>&1
    exit 0
fi

exit 0
