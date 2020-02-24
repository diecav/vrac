#!/bin/bash
api_token='h10m87RVGmmKYhrsUH1aKFV6NSo93pUFTHr64Z1PUg7d7uXx6CHvjQEnfQZOVXky'
vrac_host='https://api.mgmt.cloud.vmware.com'
integration_cs_id='1eeccfdc-aeea-4b3d-959c-462e085eefbe'
content_source_id='06064dae-6fa7-415b-9ca2-0e6473a2077b'
api_login='/iaas/api/login'
api_sync_repo='/content/api/sourcecontrol/sync-requests'

########################
#  Functions
########################

# Check sync status
get_sync_status(){
	local request_id=$1
	local sync_resp=`curl -s -X GET -H "Content-type:application/json" -H "Accept:application/json" -H "Authorization:Bearer $access_token" "$vrac_host$api_sync_repo/$request_id"`
	sync_status=$(echo "$sync_resp" | jq -r .status)
	echo "$sync_status"
}

# Check if the latest version of a blueprint is released
get_last_bp_version(){
	local bp_id=$1
	local last_bp=$(curl -s -X GET -H "Content-type:application/json" -H "Accept:application/json" -H "Authorization:Bearer $access_token" "$vrac_host/blueprint/api/blueprints/$bp_id/versions?size=1&orderBy=version+DESC" | jq .content | jq .[])
	echo "$last_bp"
}

# Get unreleased blueprint versions (assumption here is that we oly get one version - to be improved wi a loop)
get_bp_versions_by_status(){
	local bp_id=$1
	local status=$2
	local response=$(curl -s -X GET -H "Content-type:application/json" -H "Accept:application/json" -H "Authorization:Bearer $access_token" "$vrac_host/blueprint/api/blueprints/$bp_id/versions?status=$status" | jq .content | jq -c .[] | jq -r .version)
	echo "$response"
}

# Release or unrelease a blueprint version
release_unrelease_bp_version(){
	local bp_id=$1
	local bp_version=$2
	local operation=$3
	local response=$(curl -s -X POST -H "Content-type:application/json" -H "Accept:application/json" -H "Authorization:Bearer $access_token" -d '{"blueprintId": "'$bp_id'","version": "'$bp_version'"}' "$vrac_host/blueprint/api/blueprints/$bp_id/versions/$bp_version/actions/$operation")
	echo "$response"
}

# Share blueprint with all the other projects in the organization
set_bp_sharing_setting(){
	local bp_id=$1
	local bp=$(curl -s -X GET -H "Content-type:application/json" -H "Accept:application/json" -H "Authorization:Bearer $access_token" "$vrac_host/blueprint/api/blueprints/$bp_id")
	bp=$(echo "$bp" | jq '.requestScopeOrg = true')
	local response=$(curl -s -X PUT -H "Content-type:application/json" -H "Accept:application/json" -H "Authorization:Bearer $access_token" -d "$bp" "$vrac_host/blueprint/api/blueprints/$bp_id")
	echo "$response"
}

# Save and sync content source
sync_content_source(){
	local integration_cs=$(curl -s -X GET -H "Content-type:application/json" -H "Accept:application/json" -H "Authorization:Bearer $access_token" "$vrac_host/catalog/api/admin/sources/$content_source_id")
	local response=$(curl -s -X POST -H "Content-type:application/json" -H "Accept:application/json" -H "Authorization:Bearer $access_token" -d "$integration_cs" "$vrac_host/catalog/api/admin/sources")
	local cs_id=$(echo "$response" | jq -r .id)
	echo "$cs_id"
}


########################
#
#  Login and get token
#
########################
echo "Getting Access Token..."
access_token=`curl -s -X POST -H "Content-type:application/json" -H "Accept:application/json" -d '{"refreshToken": "'$api_token'"}' "$vrac_host$api_login" | jq -r .token`

if [ -z "$access_token" ]; then
	echo "Unable to retrive the access token"
	exit 1
fi
#echo "Access Token: $access_token"
echo "Access Token found!"
echo ""

########################
#
#  Sync repo
#
########################
echo "Sync git repo..."
sync_resp=`curl -s -X POST -H "Content-type:application/json" -H "Accept:application/json" -H "Authorization:Bearer $access_token" -d '{"sourceId": "'$integration_cs_id'"}' "$vrac_host$api_sync_repo"`
sync_status=$(echo "$sync_resp" | jq -r .status)
sync_request_id=$(echo "$sync_resp" | jq -r .requestId)

echo "Sync status: $sync_status"

if [[ "$sync_status" == "STARTED" ]];then
	echo "  Sync started - Polling status until change.."
	while :
	do
		sync_status=$(get_sync_status "$sync_request_id")
		case "$sync_status" in
			"REQUESTED")
				echo "  Sync status: $sync_status"
				;;
			"STARTED")
				echo "  Sync status: $sync_status"
				;;
			"PROCESSING")
				echo "  Sync status: $sync_status"
				;;
			"COMPLETED")
				echo "  Sync status: $sync_status"
				break
				;;
			"FAILED")
				echo "  Sync status: $sync_status"
				break
				;;
			"SKIPPED")
				echo "  Sync status: $sync_status - Nothing to sync."
				break
				;;
			*)
				echo "  Sync status: unknow...exit"
				exit 1
				;;
		esac
		sleep 2s
	done
fi
echo ""

##################################
#
#  Promote new templates versions
#
##################################
echo "Processing blueprints"
bp_ids=(`curl -s -X GET -H "Content-type:application/json" -H "Accept:application/json" -H "Authorization:Bearer $access_token" "$vrac_host/blueprint/api/blueprints?projects=d2e5e46b-eabb-43f6-8be3-53c9d54a7370" | jq .content | jq .[] | jq -r .id`)

if [ -z "$bp_ids" ]; then
	echo "No blueprint found for the gived project"
	exit 1
else
	echo "Found blueprints:"
	for bp_id in "${bp_ids[@]}"; do
		echo "  $bp_id"
	done
fi

# For every blueprint found, if the latest version is not the released one then
# unrelease all the released versions and release the latest one

for bp_id in "${bp_ids[@]}"; do
	last_bp=$(get_last_bp_version "$bp_id")
	last_bp_status=$(echo "$last_bp" | jq -r .status)
	last_bp_version=$(echo "$last_bp" | jq -r .version)
	if [ $last_bp_status == "RELEASED" ];then
		echo "  Blueprint $bp_id IS released - $last_bp_status"
	else
		echo "  Blueprint $bp_id IS NOT released - $last_bp_status"
		echo "    Release BP..."
		# First silently unrelease the old BP versions
        old_bp_versions=$(get_bp_versions_by_status "$bp_id" "released")
        old_bp_versions=($(echo "$old_bp_versions" | tr '\n' ' '))
        for old_bp_version in "${old_bp_versions[@]}"; do
        	unrel_response=$(release_unrelease_bp_version "$bp_id" "$old_bp_version" "unrelease")
        	unrel_bp_status=$(echo "$unrel_response" | jq -r .status)
        	if [ $unrel_bp_status == "VERSIONED" ];then
			   echo "     *version $old_bp_version is now $unrel_bp_status"
		    fi
		done
		# Now release the last version
		rel_response=$(release_unrelease_bp_version "$bp_id" "$last_bp_version" "release")
		last_bp_status=$(echo "$rel_response" | jq -r .status)
		if [ $last_bp_status == "RELEASED" ];then
			echo "    Blueprint $bp_id is now $last_bp_status"
			echo ""
		fi
		# Set the Blueprint as shared across all projects
		echo "    Set bluepring shared across projects..."
		set_as_shared=$(set_bp_sharing_setting "$bp_id")
		is_shared=$(echo "$set_as_shared" | jq .requestScopeOrg)
		if [ "$is_shared" == "true" ];then
			echo "    Bluepring set as shared"
			echo ""
		else
			echo "    Unable to set blueprint as shared"
			echo ""
		fi
	fi
done


#########################
#
# Sync the content source
#
#########################
echo "Synchronize content source..."
id=$(sync_content_source)
if [ "$id" == "$content_source_id" ];then
	echo "Content source synchronization done"
	echo ""
else
	echo "Unable to synchronize content source"
	echo ""
fi



echo "=== DONE ==="

