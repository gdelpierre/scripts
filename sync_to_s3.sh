#!/usr/bin/env bash

set -e
set -x

DATE=$(date +%Y%m%d)
FILE_TO_SYNC="/tmp/file-to-sync-"$DATE".txt"

## Create list
create_list()
{
	local tmp_dir="/tmp"
	local folders_file="$tmp_dir/folders-$DATE.txt"
	local orphans_file="$tmp_dir/files-$DATE.txt"
	
	local root_find_dir=""
	list_dirs=(
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

	( cat "$folders_file" |\ 
	  xargs -L1 -P100 -I % bash -c ' export log="%" ; find % -ctime 1 -type f > "$tmp_dir"/files-"${log//\//-}".txt ' & )
}

clean_list_of_files_to_sync()
{
	local concat_file="$tmp_dir/concat-$DATE.txt"

	# Concatenate files
	printf "Concatenation of all the files...\n"

	cat "$tmp_dir"/files{,-*} >> "$concat_file"

	# Delete dupplicate entry
	printf "Dupplicate entry in files log...\n"

	awk '!dup[$0]++' "$concat_file" > "$FILE_TO_SYNC"
}

upload_files()
{
	local err_log="upload-err.log"
	local bucket=""

	cat "$FILE_TO_SYNC" |\
	  xargs -L1 -P50 -I % s3cmd put % "$bucket"/% --preserve --server-side-encryption --multipart-chunk-size-mb=100MB 
	
}

check_upload()
{
	local upload_file=$(shuf -n 10 "$FILE_TO_SYNC")
	local err_log="check-err.log"
	local bucket=""

	while read -r file; do

		s3cmd info "$bucket"/"$file"

		if [ "$?" != 0 ] ; then
			printf "ERR! $upload_file not found upstream\n" 1>"$err_log"
		fi

	done <<< "$upload_file"
}

clean_tmp_files()
{
}
