#!/bin/bash

# This script automates the deployment of the Azure MCP Server.
# It builds a new Docker image, pushes it to Azure Container Registry,
# and deploys/updates an App Service to use the new image.

# Stop on any error
set -e

# --- Configuration ---
# You can change these variables if your resource names are different.
RESOURCE_GROUP="mcp-server-rg-2"
ACR_NAME="mcpserverregistrym2jy44rp2eo7s"
IMAGE_NAME="mcp-server"
IMAGE_TAG="latest"
BICEP_FILE="infra/deploy-mcp-server.bicep"

# --- Derived Variables ---
ACR_LOGIN_SERVER="$ACR_NAME.azurecr.io"
FULL_IMAGE_NAME="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"

# --- Script ---
echo "🚀 Starting deployment..."

# Check for any ongoing deployments and cancel them.
# Using a while loop to correctly handle deployment names that might contain spaces.
az deployment group list --resource-group "$RESOURCE_GROUP" --query "[?properties.provisioningState=='Running'].name" -o tsv | while IFS= read -r deployment; do
  if [[ -n "$deployment" ]]; then
    echo "Found an ongoing deployment: $deployment. Cancelling it..."
    az deployment group cancel --resource-group "$RESOURCE_GROUP" --name "$deployment"
    echo "Waiting for cancellation of '$deployment' to complete..."
    az deployment group wait --name "$deployment" --resource-group "$RESOURCE_GROUP" --canceled
    echo "Deployment '$deployment' cancelled."
  fi
done

echo "Step 1/5: Logging in to Azure Container Registry: $ACR_NAME"

# Enable admin user to get credentials for a more reliable login
echo "Enabling admin user on ACR to fetch credentials..."
az acr update --name $ACR_NAME --resource-group $RESOURCE_GROUP --admin-enabled true

# Fetch credentials
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "username" -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "passwords[0].value" -o tsv)

# Login using Docker
echo "Logging in to ACR using Docker..."
echo $ACR_PASSWORD | docker login $ACR_LOGIN_SERVER -u $ACR_USERNAME --password-stdin

echo "Step 2/5: Building the Docker image..."
docker build --platform linux/amd64 -t $IMAGE_NAME:$IMAGE_TAG .

echo "Step 3/5: Tagging the image for ACR: $FULL_IMAGE_NAME"
docker tag $IMAGE_NAME:$IMAGE_TAG $FULL_IMAGE_NAME

echo "Step 4/5: Pushing the image to ACR..."
docker push $FULL_IMAGE_NAME

echo "Step 5/5: Deploying Bicep template..."
# We capture the output of the deployment to get the App Service name and URL
deployment_output=$(az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$BICEP_FILE" \
  --parameters dockerImage="$FULL_IMAGE_NAME")

# Read outputs into variables using a single jq call
read -r app_service_name app_service_url <<< "$(echo "$deployment_output" | jq -r '.properties.outputs | "\(.appServiceName.value) \(.appServiceUrl.value)"')"

echo "App Service Name is: $app_service_name"

echo "Granting App Service pull permissions from ACR..."
# Get the App Service's managed identity principal ID
# It can take a moment for the principal ID to become available after deployment.
principal_id=""
for i in {1..10}; do # Increased retries to handle delays
  principal_id=$(az webapp identity show --name "$app_service_name" --resource-group "$RESOURCE_GROUP" --query "principalId" -o tsv)
  if [[ -n "$principal_id" ]]; then
    echo "Found principal ID: $principal_id"
    break
  fi
  echo "Waiting for managed identity principal ID... (attempt $i)"
  sleep 15 # Increased sleep time
done

if [[ -z "$principal_id" ]]; then
  echo "Error: Failed to retrieve principal ID for App Service '$app_service_name'."
  exit 1
fi

# Get the ACR's resource ID
# Adding retry logic here as well to be safe
acr_id=""
for i in {1..10}; do
  acr_id=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
  if [[ -n "$acr_id" ]]; then
      echo "Found ACR resource ID: $acr_id"
      break
  fi
  echo "Waiting for ACR to be discoverable... (attempt $i)"
  sleep 15
done

if [[ -z "$acr_id" ]]; then
  echo "Error: Failed to retrieve resource ID for ACR '$ACR_NAME'."
  exit 1
fi

# Assign AcrPull role to the App Service's identity for the ACR scope
# This command will fail gracefully if the role is already assigned.
az role assignment create \
  --assignee-object-id "$principal_id" \
  --scope "$acr_id" \
  --role "AcrPull" \
  --assignee-principal-type "ServicePrincipal" || echo "Role assignment may already exist."

# App Service needs to be restarted to pick up new role assignment and image settings
echo "Restarting App Service to apply changes..."
az webapp restart --name "$app_service_name" --resource-group "$RESOURCE_GROUP"

echo "✅ Deployment successful!"
echo "Your App Service '$app_service_name' has been deployed/updated."
echo "It will be available at: https://$app_service_url"
echo "Note: It may take a few minutes for the new container to start and become available." 