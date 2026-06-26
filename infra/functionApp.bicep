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

@description('Application Insights connection string. Leave empty to disable Function App telemetry wiring.')
param applicationInsightsConnectionString string = ''

@description('Tags applied to every resource.')
param tags object = {}

// uniqueString() returns a deterministic 13-char hash, so the name is always
// 15 chars long: within the 3-24 char Storage account limit and globally unique.
var storageAccountName = toLower('fn${uniqueString(resourceGroup().id, functionAppName, location)}')

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
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
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

var baseAppSettings = [
  {
    name: 'AzureWebJobsStorage__blobServiceUri'
    value: storage.properties.primaryEndpoints.blob
  }
  {
    name: 'AzureWebJobsStorage__queueServiceUri'
    value: storage.properties.primaryEndpoints.queue
  }
  {
    name: 'AzureWebJobsStorage__tableServiceUri'
    value: storage.properties.primaryEndpoints.table
  }
  {
    name: 'AzureWebJobsStorage__credential'
    value: 'managedidentity'
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
    value: '~22'
  }
  {
    // Enables Microsoft Entra ID authentication to Cosmos DB via the
    // Function App's system-assigned managed identity.
    name: 'COSMOS_ENDPOINT'
    value: cosmosEndpoint
  }
]

var telemetryAppSettings = empty(applicationInsightsConnectionString) ? [] : [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: applicationInsightsConnectionString
  }
]

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
      linuxFxVersion: 'Node|22'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: concat(baseAppSettings, telemetryAppSettings)
    }
  }
}

var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
var storageQueueDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
var storageTableDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
var storageAccountContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')

resource functionStorageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, storageBlobDataOwnerRoleId)
  scope: storage
  properties: {
    roleDefinitionId: storageBlobDataOwnerRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionStorageQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, storageQueueDataContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: storageQueueDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionStorageTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, storageTableDataContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: storageTableDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionStorageAccountContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, storageAccountContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: storageAccountContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('The resource ID of the Function App (used to link it as a SWA backend).')
output functionAppId string = functionApp.id

@description('The name of the Function App.')
output functionAppName string = functionApp.name

@description('The principal ID of the Function App system-assigned managed identity.')
output principalId string = functionApp.identity.principalId
