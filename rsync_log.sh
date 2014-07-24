#!/usr/bin/env bash

#set -x
set -o nounset
set -o errexit

readonly SSH_KEY=""
#readonly SPLIT=$(type -P split)
readonly RSYNC=$(type -P rsync)
readonly MKDIR=$(type -P mkdir)
readonly FIND=$(type -P find)
readonly CURL=$(type -P curl)
#readonly SED=$(type -P sed)
#readonly AWK=$(type -P awk)
#readonly GREP=$(type -P grep)
#readonly CUT=$(type -P cut)

readonly URL=""

readonly RSYNC_OPTS="-rlpD --update -z --include '*/' --include '*.gz' --exclude '*' --prune-empty-dirs \
                     -e 'ssh -p2121 -l root -i $SSH_KEY -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes'"
readonly CURL_OPTS="-X GET"

## Split json file with server's information.
#readonly HOSTS=$(${CURL} ${CURL_OPTS} ${URL} |
#               ${SED} -e 's/\\\\\//\//g' -e 's/[{}]//g' |
#               ${AWK} -v k="text" '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' |
#               ${SED} -e 's/\"\:\"/\|/g' -e 's/[\,]/ /g' -e 's/\"//g' |
#               ${GREP} -w -e "name" -e "hosted_domain" | ${CUT} -d"|" -f2 | tr '\n' '.')
readonly HOSTS=$(${CURL} ${CURL_OPTS} ${URL})
readonly LOG_FILE="log.txt"
readonly RMT_LOG_DIR="/var/log/"
readonly BKP_DIR="/var/backups"
readonly YEAR=$(date +'%Y')
readonly TODAY=$(date +%Y%m%d)
#readonly MAX_JOBS=$(getconf _NPROCESSORS_ONLN)

__backup()
{
         while read line; do
                local full_bkp_dir="${BKP_DIR}/${line}/${YEAR}"
                local full_rsync_func="${RSYNC} ${RSYNC_OPTS} ${line}:${RMT_LOG_DIR} ${full_bkp_dir}/"
                if [[ ! -d "${full_bkp_dir}" ]] ; then
                        ${MKDIR} -p "${full_bkp_dir}" && eval "${full_rsync_func}"  ||
                        echo "Create dir ${full_bkp_dir} failed, continue" >> "${BKP_DIR}/${LOG_FILE}-${TODAY}" 2>&1
                else
                        eval "${full_rsync_func}" || echo "Rsync ${line} failed" >> "${BKP_DIR}/${LOG_FILE}-${TODAY}" 2>&1
                fi
        done <<< "${HOSTS}"
}

__cleanup()
{
        local cleanup_time="366"
        local cleanup_func="${FIND} ${BKP_DIR} ${FIND_OPTS}"
        eval "${cleanup_func}"
}

__send_mail()
{
        local from=""
        local to=""
        mail -a "From: $from" -s "Logs backup" "$to"
}

__backup

exit 0

failed_srv=$(cat "$BKP_DIR/$LOG_FILE-$TODAY")
if [ $(wc -l < "$BKP_DIR/$LOG_FILE-$TODAY") -gt 0 ] ; then
        cat <<EOF |
Hello Adminz,

If you receive this, something went wrong for thoses servers:

$failed_srv

With love,

EOF
        __send_mail
        exit 0
else
        echo -e "$TODAY: Script failed to run" >> "$BKP_DIR"/rsync-failed.log 2>&1
        exit 1
fi

#split_file()
#{
#  total_lines=$(wc -l < ${HOST_FILE})
#  ((lines_per_file = (total_lines + MAX_JOBS - 1) / MAX_JOBS))
#
#  ${SPLIT} --lines=${lines_per_file} ${HOST_FILE} ${HOST_FILE_SPLIT}
#}

#split_file
#for file in $(ls "$HOST_FILE_SPLIT"*)
#{
#  jobs_running=0
#  while [ "$jobs_running" -lt "$MAX_JOBS" ]
#  do
#  {
#    {
#      #while read line
#      #  do
#      #    echo -e "$line \n"
#      #  done < "$file"
#      echo "a"
#    } &
#      #fork_job &
#      jobs_running=$(expr "$jobs_running" + 1)
#  }
#  done
#  wait
#}
