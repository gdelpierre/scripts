#!/bin/bash

export VAULT_PATH=""
export ANSIBLE_M6WEB_PATH=""
export ANSIBLE_CONFIG=""
export ANSIBLE_VAULT_PASSWORD_FILE="/tmp/vault_password"
export PYTHONWARNINGS="ignore:Unverified HTTPS request"

added=($(echo "$payload" | jq ".head_commit.added" | sed 's/\[//g;s/\"files\/\(.*\)\"/\1/;s/\,//;s/\]//;'))
removed=($(echo "$payload" | jq ".head_commit.removed" | sed 's/\[//g;s/\"files\/\(.*\)\"/\1/;s/\,//;s/\]//;'))
modified=($(echo "$payload" | jq ".head_commit.modified" | sed 's/\[//g;s/\"files\/\(.*\)\"/\1/;s/\,//;s/\]//;'))
message=$(jq '.head_commit.message' <<< "${payload}")

if test "${message#*Merge}" == "$message" ; then
	printf "Nothing to do, not a merge\n"
	exit 0

else
	printf "It's a merge !\n"

	containsElement ()
	{
		local e
		for e in "${@:2}"
		do
			if echo "$e" | grep -q ".*-$1"
				then return 0
			fi
		done
		return 1
	}

	i=0 ; j=0 ; k=0 ; l=0
	for f in "${added[@]}" "${removed[@]}" "${modified[@]}"
	do
		if containsElement "preprod" "$f"
			then i=$(($i+1))
 		elif containsElement "dev" "$f"
			then j="1337"
		elif containsElement "prod" "$f"
			then k=$(($k+1))
		else
			l="1337"
		fi
	done

	if [[  "$i" > 0 || "$k" > 0 ]] ; then
		# update-galaxy-requirements
		printf "update-galaxy-requirements ongoing, waiting for 45 seconds\n"
		sleep 45

		workdir="/srv/data/ansible/ansible/current/"

		if [ -f "/usr/local/bin/virtualenvwrapper.sh" ]; then
			source /usr/local/bin/virtualenvwrapper.sh
		else
			"Virtualenvwrapper not installed"
			exit 1
		fi

		venv=$(workon ansible2)
		if [ $? -eq 1 ]; then
			mkvirtualenv ansible2
		fi

		workon ansible2

		if [[ "$i" > 0 ]] ; then
		cd "${workdir}" &&
		ansible-playbook -i inventory playbooks/utility/deploy_supervisor_configs.yml -e host=preprod-wrk
		fi

		if [[ "$k" > 0 ]] ; then
		cd "${workdir}" &&
		ansible-playbook -i inventory playbooks/utility/deploy_supervisor_configs.yml -e host=prod-wrk
		fi

	else
		exit 1
	fi
fi
