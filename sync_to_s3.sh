#!/usr/bin/env bash

set -o errexit ## == set -e
set -o nounset
#set -o verbose ## == set -v
set -o xtrace ## == set -x

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
	  xargs -L1 -P100 -I % bash -c ' export log="%" ; export tmp_dir="/tmp" ; find % -ctime 1 -type f > "$tmp_dir"/files"${log//\//-}".txt ' &

	wait

}

concat_and_clean()
{
	local concat_file="$DIR_TMP/concat-$DATE.txt"

	# Concatenate files
	printf "Concatenation of all the files...\n"

	cat "$DIR_TMP"/files-*.txt >> "$concat_file"

	# Delete dupplicate entry
	printf "Dupplicate entry in files log...\n"

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

		s3cmd put $file $bucket_aws/${file:19} ${s3cmd_opts[@]} ' &

	wait
	
}

check_upload()
{
	local err_log="/tmp/check-err.log"
	local file=""
	local return_code=""
	local s3cmd_opts="-c s3cmd.cfg"
	local upload_file=$(shuf -n 10 "$FILE_TO_SYNC")

	printf "Verifying files on bucket...\n"

	while read -r file; do

		s3cmd info "$BUCKET_AWS"/"${file:19}" ${s3cmd_opts} 2>>"$err_log" 1>/dev/null
		return_code=$(echo "$?")

		if [[ "$return_code" == 12 ]] ; then
			printf "ERR! $upload_file not found upstream\n" 1>>"$err_log"
		elif [[ "$return_code" != 0 ]] ; then
			printf "ERR! An error was occured while verifying $upload_file\n" 1>>"$err_log"
		fi

	done <<< "$upload_file"

	printf "No errors reported.\n"
}

create_list
concat_and_clean
upload_files
check_upload
