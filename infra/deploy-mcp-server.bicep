@description('The location to deploy the resources.')
param location string = 'westus'

@description('The name of the App Service Plan.')
param appServicePlanName string = 'mcp-server-plan'

@description('The name of the App Service.')
param appServiceName string = 'mcp-server-${uniqueString(resourceGroup().id)}'

@description('The Docker image to deploy.')
param dockerImage string

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'F1'
    tier: 'Free'
    size: 'F1'
    family: 'F'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource appService 'Microsoft.Web/sites@2022-09-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'DOCKER|${dockerImage}'
      acrUseManagedIdentityCreds: true
      appSettings: [
        {
          name: 'AZURE_MCP_INCLUDE_PRODUCTION_CREDENTIALS'
          value: 'true'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
      ]
    }
    httpsOnly: true
  }
}

output appServiceUrl string = 'https://${appService.properties.defaultHostName}'
output principalId string = appService.identity.principalId 
