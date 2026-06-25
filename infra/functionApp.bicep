// Provisions a standalone Linux Azure Function App (with its own storage
// account and Linux Consumption plan) to host the schede API.
//
// Unlike the Static Web Apps managed Functions, a dedicated Function App
// exposes a proper IMDS endpoint, so DefaultAzureCredential can obtain a token
// from the system-assigned managed identity and Cosmos DB Entra ID (AAD)
// authentication works at runtime. (The SWA managed runtime only exposes the
// legacy MSI_ENDPOINT, which makes @azure/identity misroute to the Cloud Shell
// credential and fail with "Cannot read properties of undefined (reading
// 'expires_on')".)

targetScope = 'resourceGroup'

@description('Name of the Function App that hosts the API.')
param functionAppName string

@description('Location for the Function App, storage account and plan.')
param location string

@description('Cosmos DB account endpoint to expose as the COSMOS_ENDPOINT app setting.')
param cosmosEndpoint string

@description('Tags applied to every resource.')
param tags object = {}

// uniqueString() returns a deterministic 13-char hash, so the name is always
// 15 chars long: within the 3-24 char Storage account limit and globally unique.
var storageAccountName = toLower('fn${uniqueString(resourceGroup().id, functionAppName)}')

// Storage account required by the Azure Functions runtime.
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

// Linux Consumption (serverless) plan keeps the Function App pay-per-use.
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}'

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    reserved: true
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Node|20'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~20'
        }
        {
          // Enables Microsoft Entra ID authentication to Cosmos DB via the
          // Function App's system-assigned managed identity.
          name: 'COSMOS_ENDPOINT'
          value: cosmosEndpoint
        }
      ]
    }
  }
}

@description('The resource ID of the Function App (used to link it as a SWA backend).')
output functionAppId string = functionApp.id

@description('The name of the Function App.')
output functionAppName string = functionApp.name

@description('The principal ID of the Function App system-assigned managed identity.')
output principalId string = functionApp.identity.principalId
