#!/usr/bin/env bash

set -o errexit  ## == set -e
set -o nounset  ## == set -u
set -o pipefail

## debug purpose.
#set -o verbose  ## == set -v
#set -o xtrace   ## == set -x

BUCKET_AWS="s3://"
DATE=$(date +%Y%m%d)
YESTERDAY=$(date +%Y%m%d -d "yesterday")
DIR_TMP="/tmp"
FILE_TO_SYNC="$DIR_TMP/files-to-sync-$DATE.txt"
DAY_LOG="$DIR_TMP/$0-$DATE"
FROM="from@fqdn.tld"
TO="foo@bar.baz"

trap to_do_on_trap SIGHUP SIGINT SIGQUIT SIGTERM

send_mail()
{
	local from="$1"
	local to="$2"
	local subject="$3"
	mail -a "From: $from" -s "$DATE - $subject" "$to"
}

send_day_log()
{
	local subject="$1"
	[[ -s "$DAY_LOG" ]] && cat "$DAY_LOG" || echo "File log is empty" |
	send_mail "$FROM" "$TO" "$1"
}

to_do_on_trap()
{
	send_day_log "ERR: Script was trapped !"
	exit 1
}

## Check when the script was launched for the last time and when it was successfully.
#  If day file, already exists, exit 1.
[[ -a "$DAY_LOG" ]] &&
{
	printf "Day file already exists, check it out.\n"
	echo "File \"$DAY_LOG\" is already present." | 
	send_mail "$FROM" "$TO" "ERR: Something went wrong"
	exit 1
}

#  Touch new file when script starts.
touch "$DAY_LOG"

## Test if binary are presents.
for bin in mail s3cmd; do
	type -P "$bin" >/dev/null 2>&1 || 
	{ 
		printf "I require $bin but it's not installed.\nAborting.\n" | 
		tee -a "$DAY_LOG"
		# We use this trick rather than exit 1 in order to use the trap system.
		kill -1 $$
	}
done

# Test the bucket
s3cmd ls "$BUCKET_AWS" 2>&1 >/dev/null -c s3cmd.cfg ||
	{
	printf "Bucket unreachable\n" |
	tee -a "$DAY_LOG"
	# We use this trick rather than exit 1 in order to use the trap system.
	kill -1 $$
	}

create_list()
{
	local folders_file="$DIR_TMP/folders-$DATE.txt"
	local log=""
	local orphans_file="$DIR_TMP/files-$DATE.txt"
	local tmp_dir=""
	local root_find_dir="/"
	list_dirs=(
		"bar/baz"
		"foo/bar/baz"
		"bar/baz"
		"baz/foo"
		"foo/bar/baz"
		"foo/bar/baz"
		"baz/foo"
	)

	# of dirs.
	printf "Creating list of dirs...\n" | tee -a "$DAY_LOG"

	for dir in "${list_dirs[@]}"; do
		find "$root_find_dir$dir" -maxdepth 1 -type d >> "$folders_file"

		# clean the parent dir.
		sed -i "0,\#$root_find_dir$dir# s###" "$folders_file"
		# then remove empty line.
		sed -i '/^$/d' "$folders_file"
	done

	# of orphans files.
	printf "Scanning if new orphans files...\n" | tee -a "$DAY_LOG"
	
	for dir in "${list_dirs[@]}" "${list_dirs[1]%%/*}" \
		"${list_dirs[1]%/*/*}" "${list_dirs[4]%/*}" \
		"${list_dirs[5]%/*}" "${list_dirs[6]%/*}" ; do
		find "$root_find_dir$dir" -maxdepth 1 -ctime 0 -type f >> "$orphans_file"
	done

	# of dirs file compute above.
	# ctime 0 => find files modified between now and 1 day ago.
	printf "Scanning if new files...\n" | tee -a "$DAY_LOG"

	cat "$folders_file" |
	  xargs -L1 -P100 -I % bash -c ' \
		export log="%" ; \
		export tmp_dir="/tmp" ; \
		find % -ctime 0 -type f > "$tmp_dir"/files"${log//\//-}".txt ' &

	wait
}

concat_and_clean()
{
	local concat_file="$DIR_TMP/concat-$DATE.txt"

	# Concatenate files
	printf "Concatenation of all the files...\n" | tee -a "$DAY_LOG"

	cat "$DIR_TMP"/files-*.txt >> "$concat_file"

	# Delete duplicate entry
	printf "Delete duplicate entry in files log...\n" | tee -a "$DAY_LOG"

	awk '!dup[$0]++' "$concat_file" > "$FILE_TO_SYNC"
}

upload_files_to_s3()
{
	local err_log=""
	local file=""
	local s3cmd_opts=()

	printf "Sync'ing files, could take a while...\n" | tee -a "$DAY_LOG"

	cat "$FILE_TO_SYNC" |
	    xargs -L1 -P30 -I % bash -c ' \
		export bucket_aws="s3://" ; \
		export file="%" ; \
		export err_log="upload-err.log" \
		export s3cmd_opts=("--preserve"
                        "--server-side-encryption"
                        "--multipart-chunk-size-mb=100"
                        "-c /root/test/s3cmd.cfg"
                        ) ; \

		s3cmd put $file $bucket_aws${file:12} ${s3cmd_opts[@]} >/tmp/log.log 2>&1 ' &

	wait
}

check_s3_upload()
{
	# We test all the uploaded files.
	local count=$(( $(wc -l < "$FILE_TO_SYNC") ))
	local err_log="/tmp/check-err.log"
	local line=""
	local return_code=""
	local s3cmd_opts="-c ~/s3cmd.cfg"
	local tested_files=0

	# move log file if present and not empty.
        ( [[ -a "$err_log" ]] && [[ -s "$err_log" ]] ) &&
        mv "$err_log" "$err_log-$YESTERDAY" ||
        rm "$err_log"

	printf "Verifying files on bucket...\n" | tee -a "$DAY_LOG"

	while read -r line; do

		return_code=$(s3cmd info "$BUCKET_AWS"/"${line:12}" ${s3cmd_opts} >/dev/null 2>&1 ; echo $?)

		if [[ "$return_code" == 12 ]] ; then
			printf "ERR! $line not found upstream\n" 2>>"$err_log"
			tested_files=$(( ${tested_files} - 1 ))
		elif [[ "$return_code" != 0 ]] ; then
			printf "ERR! An error was occured while verifying $line\n" 2>>"$err_log"
			tested_files=$(( ${tested_files} - 1 ))
		fi

		tested_files=$(( ${tested_files} + 1 ))

	done < "$FILE_TO_SYNC"

	printf "=> %d files tested, %d OK\n" "$count" "$tested_files" | tee -a "$DAY_LOG"
	
	if [[ -a "$err_log" ]] || [[ "$count" != ${tested_files} ]]; then
		cat "err_log" >> "$DAY_LOG"
		printf "Error(s) detected.\nPlease check $err_log\n" | tee -a "$DAY_LOG"
		send_day_log "ERR: Error during upload detected."
		exit 1
	else
		printf "No errors reported.\n" | tee -a "$DAY_LOG"
	fi
}

clean()
{
	local file=""
	for file in "$DIR_TMP"/{files,folders,concat}-*.txt; do
		[[ -f "$file" ]] && rm "$file"
	done

	[[ -a "${DAY_LOG/$DATE/$YESTERDAY}" ]] &&
	rm ${DAY_LOG/$DATE/$YESTERDAY}
}

sleep 100

create_list
concat_and_clean
upload_files_to_s3
check_s3_upload
clean
send_day_log "Backup day log."
exit 0
