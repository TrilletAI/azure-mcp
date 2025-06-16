#!/bin/bash

# This script deploys the core infrastructure for the MCP server,
# including the Resource Group and the Azure Container Registry.
# This typically only needs to be run once.

set -e

BICEP_FILE="infra/deploy-infra.bicep"
LOCATION="westus" # Or your preferred Azure region

echo "🚀 Starting infrastructure deployment..."

deployment_output=$(az deployment sub create \
  --location "$LOCATION" \
  --template-file "$BICEP_FILE")

acr_name=$(echo "$deployment_output" | jq -r '.properties.outputs.acrName.value')

if [[ -z "$acr_name" ]]; then
    echo "Error: ACR name not found in deployment output."
    exit 1
fi

echo "✅ Infrastructure deployment successful!"
echo "Your Azure Container Registry is named: $acr_name"
echo "Please update your 'redeploy.sh' script with this ACR name." 