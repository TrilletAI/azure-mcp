@description('The location to deploy the resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('The name of the App Service Plan.')
param appServicePlanName string = 'mcp-server-plan'

@description('The name of the App Service.')
param appServiceName string = 'mcp-server-${uniqueString(resourceGroup().id)}'

@description('The SKU for the App Service Plan.')
param appServicePlanSku string = 'S1' // Standard tier, better for performance

@description('The Docker image to deploy from ACR.')
param dockerImage string

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: appServicePlanSku
  }
  properties: {
    reserved: true // This is required for Linux plans
  }
}

resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: appServiceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|${dockerImage}'
      appCommandLine: '/app/azmcp server start --transport sse'
      alwaysOn: true // Requires B1 SKU or higher
      acrUseManagedIdentityCreds: true
      appSettings: [

      ]
    }
  }
}

output appServiceName string = appService.name
output appServiceUrl string = appService.properties.defaultHostName
