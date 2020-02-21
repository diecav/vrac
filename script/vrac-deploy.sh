#!/bin/bash
api_token='h10m87RVGmmKYhrsUH1aKFV6NSo93pUFTHr64Z1PUg7d7uXx6CHvjQEnfQZOVXky'
vrac_host='https://api.mgmt.cloud.vmware.com'
content_source_id='1eeccfdc-aeea-4b3d-959c-462e085eefbe'
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


########################
#
#  Sync repo
#
########################
echo "Sync git repo..."
sync_resp=`curl -s -X POST -H "Content-type:application/json" -H "Accept:application/json" -H "Authorization:Bearer $access_token" -d '{"sourceId": "'$content_source_id'"}' "$vrac_host$api_sync_repo"`
sync_status=$(echo "$sync_resp" | jq -r .status)
sync_request_id=$(echo "$sync_resp" | jq -r .requestId)

echo "Sync status: $sync_status"
echo "requestId: $sync_request_id"

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
		sleep 1s
	done
fi

echo "=== DONE ==="

