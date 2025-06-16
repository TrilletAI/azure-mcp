targetScope = 'subscription'

@description('The name of the resource group to create or use.')
param resourceGroupName string = 'mcp-server-rg-2'

@description('The location for the resources.')
param location string = 'westus'

@description('A unique name for the Azure Container Registry.')
param acrName string = 'mcpserverregistry${uniqueString(subscription().subscriptionId, resourceGroupName)}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module acr './modules/acr.bicep' = {
  name: 'acrDeployment'
  scope: resourceGroup
  params: {
    acrName: acrName
    location: location
  }
}

output acrName string = acr.outputs.acrName
output acrLoginServer string = acr.outputs.acrLoginServer 
