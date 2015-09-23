#!/usr/bin/env bash

set -o errexit  ## == set -e
set -o nounset  ## == set -u
set -o pipefail

## debug purpose.
#set -o verbose  ## == set -v
#set -o xtrace   ## == set -x

BUCKET_AWS=""
DATE=$(date +%Y%m%d)
DIR_TMP="/tmp"
FILE_TO_SYNC="$DIR_TMP/file-to-sync-$DATE.txt"

create_list()
{
	local folders_file="$DIR_TMP/folders-$DATE.txt"
	local log=""
	local orphans_file="$DIR_TMP/files-$DATE.txt"
	local tmp_dir=""

	local root_find_dir=""
	local list_dirs=(
			"foo"
			"bar/baz/foo"
			"bar"
			"baz"
			"baz/bar"
			"flunk/rimshot"
			)

	# of dirs.
	printf "Creating list of dirs...\n"

	for dir in "${list_dirs[@]}"; do
		find "$root_find_dir$dir" -maxdepth 1 -type d >> "$folders_file"

		# clean the parent dir.
		sed -i "0,\#$root_find_dir$dir# s###" "$folders_file"
		# then remove empty line.
		sed -i '/^$/d' "$folders_file"
	done

	# of orphans files.
	printf "Scanning if new orphans files...\n"
	
	for dir in "${list_dirs[@]}" "${list_dirs[1]%%/*}" "${list_dirs[4]%%/*}" "${list_dirs[5]%%/*}"; do
		find "$root_find_dir$dir" -maxdepth 1 -ctime 1 -type f >> "$orphans_file"
	done

	# of dirs file compute above.
	printf "Scanning if new files...\n"

	cat "$folders_file" |
	  xargs -L1 -P100 -I % bash -c ' \
		export log="%" ; \
		export tmp_dir="/tmp" ; \
		find % -ctime 1 -type f > "$tmp_dir"/files"${log//\//-}".txt ' &

	wait
}

concat_and_clean()
{
	local concat_file="$DIR_TMP/concat-$DATE.txt"

	# Concatenate files
	printf "Concatenation of all the files...\n"

	cat "$DIR_TMP"/files-*.txt >> "$concat_file"

	# Delete duplicate entry
	printf "Delete duplicate entry in files log...\n"

	awk '!dup[$0]++' "$concat_file" > "$FILE_TO_SYNC"
}

upload_files()
{
	local err_log=""
	local file=""
	local s3cmd_opts=()

	printf "Sync'ing files, could take a while...\n"

	cat "$FILE_TO_SYNC" |
	    xargs -L1 -P15 -I % bash -c ' \
		export bucket_aws="" ; \
		export file="%" ; \
		export err_log="upload-err.log" \
		export s3cmd_opts=("--preserve"
                        "--server-side-encryption"
                        "--multipart-chunk-size-mb=100"
                        "-c s3cmd.cfg"
                        ) ; \

		s3cmd put $file $bucket_aws/${file:19} ${s3cmd_opts[@]} >/dev/null 2>&1 ' &

	wait
}

check_upload()
{
	# We test 50% of uploaded files.
	local count=$(( $(wc -l < "$FILE_TO_SYNC") / 2))
	local err_log="/tmp/check-err.log"
	local file=""
	local return_code=""
	local s3cmd_opts="-c s3cmd.cfg"
	local tested_files=0
	local upload_file=$(shuf -n "$count" "$FILE_TO_SYNC")

	# empty log file
	! [[ -s "$err_log" ]] || > "$err_log"

	printf "Verifying files on bucket...\n"

	while read -r file; do

		return_code=$(s3cmd info "$BUCKET_AWS"/"${file:19}" ${s3cmd_opts} >/dev/null 2>&1 ; echo $?)

		if [[ "$return_code" == 12 ]] ; then
			printf "ERR! $file not found upstream\n" 1>>"$err_log"
			tested_files=$(( ${tested_files} - 1 ))
		elif [[ "$return_code" != 0 ]] ; then
			printf "ERR! An error was occured while verifying $file\n" 1>>"$err_log"
			tested_files=$(( ${tested_files} - 1 ))
		fi

		tested_files=$(( ${tested_files} + 1 ))

	done <<< "$upload_file"

	printf "=> %d files tested, %d OK\n" "$count" "$tested_files"

	if [[ -s "$err_log" ]]; then
		printf "No errors reported.\n"
	else
		printf "Error(s) detected.\nPlease check $err_log\n"
		exit 1
	fi
}

clean_tmp_file()
{
	rm "$FILE_TO_SYNC"
}

clean_tmp_files_on_failure()
{
	local file=""
	for file in "$DIR_TMP"/{files,folders,concat}-*.txt; do
		[[ -f "$file" ]] && rm "$file"
	done
}

trap clean_tmp_files_on_failure EXIT SIGHUP SIGKILL SIGINT
create_list
concat_and_clean
upload_files
check_upload
clean_tmp_file
exit 0
