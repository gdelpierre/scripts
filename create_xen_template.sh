#!/usr/bin/env bash

DATE=$(date +"%Y%m%d")
DATE_Y=$(date -d "yesterday" "+%Y%m%d")
VM_UUID="668aae39-1470-8910-303b-0e3c1ac6ae12"
SNAP_LABEL="template"_"${DATE}"
OLD_SNAP_LABEL="template"_"${DATE_Y}"

# Create snapshot
create_snapshot()
{
	xe vm-snapshot uuid="$VM_UUID" new-name-label="$SNAP_LABEL" new-name-description="$SNAP_LABEL"
	if [[ $? -eq 1 ]]; then
		exit
	fi
}

create_template()
{
	local dest_sr="46290d21-2505-c6a3-db71-eb6278e09347" # netapp storage
	# retrieve uuid of the new snap.
        local snap_uuid=$(xe snapshot-list name-label="$SNAP_LABEL" | grep '^uuid' | awk {'print $NF'})
	xe snapshot-copy uuid="$snap_uuid" sr-uuid="$dest_sr" new-name-description="$SNAP_LABEL" new-name-label="$SNAP_LABEL"
}

rename_template()
{
	# Find uuid of vdi
	local vdi_template_uuid=$(xe vbd-list vm-name-label="$SNAP_LABEL" device=hda | grep 'vdi-uuid' | awk {'print $NF'})
	# rename it
	xe vdi-param-set uuid="$vdi_template_uuid" name-label="$SNAP_LABEL" name-description="$SNAP_LABEL"
	# set VCPU = 1 and RAM = 1024 in case of master VM runs with more.
	# First retrieve uuid of template
	local template_uuid=$(xe template-list name-label="$SNAP_LABEL" | grep '^uuid' | awk {'print $NF'})
	xe template-param-set uuid="$template_uuid" VCPUs-at-startup=1 VCPUs-max=1 memory-static-max=1073741824 memory-dynamic-max=1073741824 memory-dynamic-min=1073741824 memory-static-min=134217728
}

# Delete daily snapshot
delete_dday_snapshot()
{
	# retrieve uuid of the d-1 snap.
	local snap_uuid=$(xe snapshot-list name-label="$SNAP_LABEL" | grep '^uuid' | awk {'print $NF'})
	if [[ $? -eq 1 || -z "$snap_uuid" ]]; then
		exit
	fi
	# delete it
	xe snapshot-uninstall uuid="$snap_uuid"	force=true
}

remove_old_template()
{
	# retrieve uuid of the d-1 template
	local template_uuid=$(xe template-list name-label="$OLD_SNAP_LABEL"  | grep '^uuid' | awk {'print $NF'})
	if [[ $? -eq 1 || -z "$template_uuid" ]]; then
                exit
        fi
	# delete it
	xe template-uninstall template-uuid="$template_uuid" force=true
}

create_snapshot
create_template
delete_dday_snapshot
rename_template
remove_old_template
