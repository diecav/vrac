#!/bin/bash
api_token='h10m87RVGmmKYhrsUH1aKFV6NSo93pUFTHr64Z1PUg7d7uXx6CHvjQEnfQZOVXky'


## Login and get token
access_token=`curl -X POST -H "Content-type:application/json" -H "Accept:application/json" -d '{"refreshToken": "'$api_token'"}' "https://api.mgmt.cloud.vmware.com/iaas/api/login" | jq -r .token`
echo "Access Token: $access_token"
