#!/bin/bash

# This script automates the deployment of the Azure MCP Server.
# It builds a new Docker image, pushes it to Azure Container Registry,
# and updates the App Service to use the new image.

# Stop on any error
set -e

# --- Configuration ---
# You can change these variables if your resource names are different.
RESOURCE_GROUP="mcp-server-rg"
ACR_NAME="mcpserverregistry2bf983fe"
IMAGE_NAME="mcp-server"
IMAGE_TAG="latest"
BICEP_FILE="infra/deploy-mcp-server.bicep"

# --- Derived Variables ---
ACR_LOGIN_SERVER="$ACR_NAME.azurecr.io"
FULL_IMAGE_NAME="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"

# --- Script ---
echo "🚀 Starting deployment..."

echo "Step 1/6: Logging in to Azure Container Registry: $ACR_NAME"
az acr login --name $ACR_NAME

echo "Step 2/6: Building the Docker image..."
docker build -t $IMAGE_NAME:$IMAGE_TAG .

echo "Step 3/6: Tagging the image for ACR: $FULL_IMAGE_NAME"
docker tag $IMAGE_NAME:$IMAGE_TAG $FULL_IMAGE_NAME

echo "Step 4/6: Pushing the image to ACR..."
docker push $FULL_IMAGE_NAME

echo "Step 5/6: Deploying Bicep template..."
# We capture the output of the deployment to get the App Service name
deployment_output=$(az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file $BICEP_FILE \
  --parameters dockerImage=$FULL_IMAGE_NAME \
  --query "properties.outputs.appServiceUrl.value" \
  -o tsv)
app_service_name=$(echo $deployment_output | sed 's~https://~~' | sed 's~\.azurewebsites\.net~~')

echo "App Service Name is: $app_service_name"

echo "Step 6/6: Granting App Service pull permissions from ACR..."
# Get the App Service's managed identity principal ID
principal_id=$(az webapp identity show --name $app_service_name --resource-group $RESOURCE_GROUP --query "principalId" -o tsv)

# Get the ACR's resource ID
acr_id=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "id" -o tsv)

# Assign AcrPull role to the App Service's identity for the ACR scope
# This command will fail gracefully if the role is already assigned.
az role assignment create \
  --assignee $principal_id \
  --scope $acr_id \
  --role "AcrPull" \
  --assignee-principal-type "ServicePrincipal" || echo "Role assignment may already exist."


echo "✅ Deployment successful!"
echo "Your App Service at https://$app_service_name.azurewebsites.net has been updated."
echo "Note: It may take a minute for the service to become available." 