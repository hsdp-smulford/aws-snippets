#!/bin/bash
# shellcheck disable=SC2181,SC2155,SC2207,SC2016

# Usage: ./find-eips.sh 

# While this script gets all EIPs in the organization, it is intended to be used to find this specific EIP.
EIP=1.2.3.4

# Comment out profiles not being used
AFT_MNGT_PROFILE=dev-mngt     # This is your local profile that has access to the DEV AFT Management account
AFT_MNGT_PROFILE=prod-mngt    # This is your local profile that has access to the PROD AFT Management account
PAYER_PROFILE=dev-payer       # This is your local profile that has access to the DEV Payer account
PAYER_PROFILE=prod-payer      # This is your local profile that has access to the PROD Payer account
profile=aft-management-admin  # This is the profile that will be used to assume the role in the AFT Management account
OUTPUT_FILE=/var/log/shawn/eips.log
regions=(us-east-1)

echo "[$(date)]; Starting." >> "$OUTPUT_FILE"

# Get a list of active accounts in the organization
account_ids=( $(aws organizations list-accounts \
                --profile $PAYER_PROFILE \
                --query 'Accounts[?Status==`ACTIVE`].Id' \
                --output text) )

for account_id in "${account_ids[@]}"; do
  echo "[$(date)]; Found Account IDs: $account_id" >> "$OUTPUT_FILE"
done


# Assume 'AWSAFTAdmin' role in AFT Management account
AFT_MGMT_ROLE=$(aws ssm get-parameter --profile "${AFT_MNGT_PROFILE}" --name /aft/resources/iam/aft-administrator-role-name | jq --raw-output ".Parameter.Value")
AFT_MGMT_ACCOUNT=$(aws ssm get-parameter --profile "${AFT_MNGT_PROFILE}" --name /aft/account/aft-management/account-id | jq --raw-output ".Parameter.Value")
ROLE_SESSION_NAME=$(aws ssm get-parameter --profile "${AFT_MNGT_PROFILE}" --name /aft/resources/iam/aft-session-name | jq --raw-output ".Parameter.Value")
CREDENTIALS=$(aws sts assume-role --role-arn "arn:aws:iam::${AFT_MGMT_ACCOUNT}:role/${AFT_MGMT_ROLE}" --role-session-name "${ROLE_SESSION_NAME}")

aws_access_key_id="$(echo "${CREDENTIALS}" | jq --raw-output ".Credentials[\"AccessKeyId\"]")"
aws_secret_access_key="$(echo "${CREDENTIALS}" | jq --raw-output ".Credentials[\"SecretAccessKey\"]")"
aws_session_token="$(echo "${CREDENTIALS}" | jq --raw-output ".Credentials[\"SessionToken\"]")"

aws configure set aws_access_key_id "${aws_access_key_id}" --profile "${profile}"
aws configure set aws_secret_access_key "${aws_secret_access_key}" --profile "${profile}"
aws configure set aws_session_token "${aws_session_token}" --profile "${profile}"

echo "[$(date)]; Credentials valid for: $(aws whoami --profile ${profile} --query 'Arn' --output text)" >> "$OUTPUT_FILE"

for account_id in "${account_ids[@]}"; do

      # Assume AFT role in vended account.
      echo "[$(date)]; Assuming 'AWSAFTExecution' role in the account $account_id" >> "$OUTPUT_FILE"
      creds=$(aws sts assume-role \
         --profile "${profile}" \
         --role-arn "arn:aws:iam::${account_id}:role/AWSAFTExecution" \
         --role-session-name AWSAFT-Session \
         --query 'Credentials' 2>&1)

      # Were we able to assume the role?
      if [ $? -ne 0 ]; then
        echo "[$(date)]; Unable to assume role in account $account_id" >> "$OUTPUT_FILE" 
        continue
      fi

      export AWS_ACCESS_KEY_ID=$(echo "${creds}" | jq -r '.AccessKeyId')
      export AWS_SECRET_ACCESS_KEY=$(echo "${creds}" | jq -r '.SecretAccessKey')
      export AWS_SESSION_TOKEN=$(echo "${creds}" | jq -r '.SessionToken')
      echo "[$(date)]; Assumed role: $(aws sts get-caller-identity --query 'Arn' --output text)" >> "$OUTPUT_FILE"

    for region in "${regions[@]}"; do
        echo "[$(date)]; Getting EIPs for account: $account_id; region $region" >> "$OUTPUT_FILE"
        eips=($(aws ec2 describe-addresses \
            --region "${region}" \
            --query 'Addresses[].PublicIp' \
            --output text))

        for eip in "${eips[@]}"; do
          if [[ $eip == "${EIP}" ]]; then
            echo "[$(date)]; EIP FOUND" >> "$OUTPUT_FILE"
          fi
          echo "[$(date)]; Account: $account_id; region: $region; EIP: $eip" >> "$OUTPUT_FILE"
        done
      done
done

echo "[$(date)]; Finished." >> "$OUTPUT_FILE"

