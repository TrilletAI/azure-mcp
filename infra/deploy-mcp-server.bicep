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
        {
          name: 'ASPNETCORE_HTTP_PORTS'
          value: '80'
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: 'update'
        }
        {
          name: 'AZURE_CLIENT_SECRET'
          value: 'update'
        }
        {
          name: 'AZURE_TENANT_ID'
          value: 'Update'
        }
      ]
    }
  }
}

resource authSettings 'Microsoft.Web/sites/config@2022-03-01' = {
  parent: appService
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      unauthenticatedClientAction: 'Return401'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: 'https://login.microsoftonline.com/0c2dd5df-aa62-427a-929d-cec4f822d83c'
          clientId: 'clientID'
          clientSecretSettingName: 'secret'
        }
        login: {
          loginParameters: [ 'scope=openid profile email' ]
        }
      }
    }
  }
}

output appServiceName string = appService.name
output appServiceUrl string = appService.properties.defaultHostName
