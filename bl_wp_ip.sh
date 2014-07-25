#!/usr/bin/env bash

set -x
set -o nounset
set -o errexit

# Define tools.
readonly FIND=$(type -P find)
readonly ZGREP=$(type -P zgrep)
readonly XARGS=$(type -P xargs)
readonly CUT=$(type -P cut)
readonly UNIQ=$(type -P uniq)
readonly SORT=$(type -P sort)
readonly GREP=$(type -P grep)
readonly CURL=$(type -P curl)
readonly GIT=$(type -P git)
readonly RM=$(type -P rm)

usage()
{
	echo "$0: days occurence"
}

# Check if number of arguments is correct.
if [ "$#" -ne "2" ]; then
	usage
	exit 1
fi

# Define global used variables.
SEARCH_DAY=${1}
RECCURENCE_IP=${2}

# Temporary files.
readonly TMP_FILE="/tmp/tmp_bl_parse.txt"
readonly TMP_SORT_FILE="/tmp/tmp_bl_sort.txt"
readonly TMP_BF_LIST="/tmp/tmp_bl_bruteforce.txt"

# Git Blacklist file
NEW_BL_FILE="/usr/local/bin/wp_ip_blacklist/wordpress_blacklist_ip.txt"

# find IP trying to POST on wp-admin
post_wp()
{
        local find_location="/var/backups/*/*/{apache2,nginx,varnish}/"
        local find_opts="-mtime ${SEARCH_DAY} -name '*access*' -type f -print0"
        local xargs_opts="-0"
        local zgrep_opts="-h 'POST.*wp-login\.php'"
        local cut_opts="-d- -f1"
        eval ${FIND} ${find_location} ${find_opts} |
        eval ${XARGS} ${xargs_opts} ${ZGREP} ${zgrep_opts} |
        ${CUT} ${cut_opts} >> "${TMP_FILE}"
}

# Sort and count IPs.
sort_ip()
{
	local sort_opts="-n"
	local uniq_opts="-c"
	${SORT} ${sort_opts} < "${TMP_FILE}" |
	${UNIQ} ${uniq_opts} |
	${SORT} ${sort_opts} > "${TMP_SORT_FILE}"
}

# Only keep highest reccurence of IPs.
keep_highest_ip_rate()
{
	while read count ip ; do
		if [[ "$count" -ge "$RECCURENCE_IP" ]] ; then
			echo "${ip}"
		fi
	done < "${TMP_SORT_FILE}" >> "${TMP_BF_LIST}"
}

# diff current bl and new list, keep first IP occurence, sort them and built
# a new file.
make_me_a_ragout()
{
	local sort_opts=(-u -n)
	local grep_opts="-v '^$'"
	local git_url="https://raw.githubusercontent.com/Nexylan/wp_ip_blacklist/master/wordpress_blacklist_ip.txt"
	local curl_opts="-s"
	local current_bl=/tmp/tmp_bl_current.txt
	${CURL} ${curl_opts} ${git_url} > ${current_bl}
	${SORT} ${sort_opts[0]} ${current_bl} ${TMP_BF_LIST} |
	${GREP} ${grep_opts} |
	${SORT} ${sort_opts[1]} > ${NEW_BL_FILE}
}

# Send new list.
send_list()
{
	local git_opts=('add' 'commit -m' 'push')
	local today=$(date +%Y%m%d)
	local commit_msg="\"Update blacklist - $today\""

	# Test if git is installed.
	[[ "$GIT" ]] ||
	echo -e "Git is not installed - List can not be sent ; abort"

	# Test if it's a git repo or not.
	[[ -d .git ]] || echo -e "Not a git repo"

	${GIT} ${git_opts[0]} ${NEW_BL_FILE} &&
	eval ${GIT} ${git_opts[1]} ${commit_msg} &&
	${GIT} ${git_opts[2]} || exit 1
}

clean_tmp_files()
{
	local tmp_file="/tmp/tmp_bl_*"
	${RM} ${tmp_file}
}

post_wp
sort_ip
keep_highest_ip_rate
make_me_a_ragout
send_list
clean_tmp_files

exit 0
