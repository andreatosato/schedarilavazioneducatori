// Bicep template that provisions only the Azure Cosmos DB for NoSQL
// Free Tier resources used by the "Strade Aperte" app:
//   * Cosmos DB account with the lifetime Free Tier enabled.
//   * Shared-throughput SQL database and the schede container.
//
// Everything is created automatically by a single deployment, e.g.:
//   az group create --name rg-stradeaperte --location italynorth
//   az deployment group create \
//     --resource-group rg-stradeaperte \
//     --template-file infra/main.bicep \
//     --parameters infra/main.bicepparam

targetScope = 'resourceGroup'

@description('Base name used to derive the resource names.')
param name string = 'stradeaperte'

@description('Name of the Cosmos DB account. Defaults to the base name so the account can match the Static Web App resource name.')
param cosmosAccountName string = name

@description('Location for the Cosmos DB account. Defaults to the resource group location.')
param cosmosLocation string = resourceGroup().location

@description('Enable the Cosmos DB lifetime Free Tier (1000 RU/s throughput and 25 GB storage free). Only one free-tier account is allowed per subscription, so set this to false if the subscription already has one.')
param enableCosmosFreeTier bool = true

@description('Name of the existing Static Web App whose application settings receive the Cosmos DB connection string. Defaults to the base name.')
param staticWebAppName string = name

@description('When true, sets the Cosmos DB application setting on the Static Web App. This is only needed for legacy SWA-managed Functions; the dedicated Function App receives its own setting.')
param configureStaticWebAppSettings bool = false

@description('When true, grants the Static Web App system-assigned managed identity the Cosmos DB Built-in Data Contributor role. This is only needed for legacy SWA-managed Functions.')
param assignCosmosDataRole bool = false

@description('When true, provisions a standalone Linux Azure Function App (with its own storage account and consumption plan) to host the schede API. Unlike the Static Web Apps managed Functions, a dedicated Function App fully supports managed identity, so Cosmos DB Entra ID authentication works at runtime.')
param deployFunctionApp bool = true

@description('Name of the standalone Function App that hosts the API. Defaults to "<name>-api".')
param functionAppName string = '${name}-api'

@description('When true, links the standalone Function App to the Static Web App as a "bring your own" backend so requests to /api/* are routed to it. Linked backends require the Static Web App Standard plan.')
param linkFunctionAppToStaticWebApp bool = true

@description('Location for the Function App, storage account and plan. Defaults to the resource group location.')
param functionAppLocation string = resourceGroup().location

@description('When true, provisions Application Insights and wires it to the dedicated Function App.')
param deployApplicationInsights bool = true

@description('Name of the Log Analytics workspace used by Application Insights.')
param logAnalyticsWorkspaceName string = '${name}-logs'

@description('Name of the Application Insights component used by the Function App.')
param applicationInsightsName string = '${name}-appi'

@description('Tags applied to every resource.')
param tags object = {
  project: 'strade-aperte'
}

var cosmosDatabaseName = 'schede'
var cosmosContainerName = 'schede'

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: toLower(cosmosAccountName)
  location: cosmosLocation
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: enableCosmosFreeTier
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: cosmosLocation
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}

// Shared throughput at the database level keeps the whole database within the
// 1000 RU/s covered by the Free Tier, so cost stays at zero for light usage.
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: cosmosAccount
  name: cosmosDatabaseName
  properties: {
    resource: {
      id: cosmosDatabaseName
    }
    options: {
      autoscaleSettings: {
        maxThroughput: 1000
      }
    }
  }
}

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = {
  parent: cosmosDatabase
  name: cosmosContainerName
  properties: {
    resource: {
      id: cosmosContainerName
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
    }
  }
}

// Reference the already-deployed Static Web App so the deployment can publish
// the Cosmos DB endpoint as an application setting and grant its managed
// identity access to Cosmos DB data. Using the endpoint plus AAD avoids storing
// any account key/connection string.
resource staticWebApp 'Microsoft.Web/staticSites@2024-04-01' existing = if (configureStaticWebAppSettings || assignCosmosDataRole || (deployFunctionApp && linkFunctionAppToStaticWebApp)) {
  name: staticWebAppName
}

// Setting the 'appsettings' config replaces the full set of application
// settings. COSMOS_ENDPOINT lets the Azure Functions API authenticate to
// Cosmos DB with Microsoft Entra ID (the Static Web App managed identity)
// instead of an account key, which is required when the account disables
// local (key-based) authorization (`disableLocalAuth = true`).
resource staticWebAppSettings 'Microsoft.Web/staticSites/config@2024-04-01' = if (configureStaticWebAppSettings) {
  parent: staticWebApp
  name: 'appsettings'
  properties: {
    COSMOS_ENDPOINT: cosmosAccount.properties.documentEndpoint
  }
}

// Built-in "Cosmos DB Built-in Data Contributor" data-plane role. This is a
// Cosmos DB SQL role (not an Azure RBAC role) and grants read/write access to
// the account data, which is what the Functions API needs.
var cosmosDataContributorRoleId = '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (deployFunctionApp && deployApplicationInsights) {
  name: logAnalyticsWorkspaceName
  location: functionAppLocation
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (deployFunctionApp && deployApplicationInsights) {
  name: applicationInsightsName
  location: functionAppLocation
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
  }
}

resource cosmosDataRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = if (assignCosmosDataRole) {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, staticWebAppName, '00000000-0000-0000-0000-000000000002')
  properties: {
    roleDefinitionId: cosmosDataContributorRoleId
    principalId: staticWebApp!.identity.principalId
    scope: cosmosAccount.id
  }
}

// --- Standalone "bring your own" Function App -------------------------------
// The Static Web Apps managed Functions do not support managed identity for
// outbound calls (the runtime only exposes the legacy MSI_ENDPOINT, so
// @azure/identity misroutes to the Cloud Shell credential and fails with
// "Cannot read properties of undefined (reading 'expires_on')"). A dedicated
// Function App exposes a proper IMDS endpoint, so DefaultAzureCredential can
// obtain a token and Cosmos DB Entra ID authentication works at runtime.
module functionApp 'functionApp.bicep' = if (deployFunctionApp) {
  name: 'functionAppDeployment'
  params: {
    functionAppName: functionAppName
    location: functionAppLocation
    cosmosEndpoint: cosmosAccount.properties.documentEndpoint
    applicationInsightsConnectionString: (deployFunctionApp && deployApplicationInsights) ? applicationInsights!.properties.ConnectionString : ''
    tags: tags
  }
}

resource functionAppSite 'Microsoft.Web/sites@2024-04-01' existing = if (deployFunctionApp && linkFunctionAppToStaticWebApp) {
  name: functionAppName
}

// Grant the Function App's managed identity read/write access to Cosmos DB data.
resource cosmosDataRoleAssignmentFunctionApp 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = if (deployFunctionApp) {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, functionAppName, '00000000-0000-0000-0000-000000000002')
  properties: {
    roleDefinitionId: cosmosDataContributorRoleId
    principalId: functionApp!.outputs.principalId
    scope: cosmosAccount.id
  }
}

// Link the Function App to the Static Web App so requests to /api/* are routed
// to it ("bring your own functions"). Linked backends require the Static Web
// App Standard plan.
resource linkedBackend 'Microsoft.Web/staticSites/linkedBackends@2024-04-01' = if (deployFunctionApp && linkFunctionAppToStaticWebApp) {
  parent: staticWebApp
  name: 'schede-api'
  properties: {
    backendResourceId: functionApp!.outputs.functionAppId
    region: functionAppLocation
  }
}

// Keep the API triggers anonymous. The linked backend still proxies /api/*,
// while App Service Authentication on the Function App causes proxy 503s here.
resource functionAppAuthSettings 'Microsoft.Web/sites/config@2024-04-01' = if (deployFunctionApp && linkFunctionAppToStaticWebApp) {
  parent: functionAppSite
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: false
    }
  }
  dependsOn: [
    linkedBackend
  ]
}

@description('The name of the provisioned Cosmos DB account.')
output cosmosAccountName string = cosmosAccount.name

@description('The name of the provisioned Cosmos DB SQL database.')
output cosmosDatabaseName string = cosmosDatabase.name

@description('The name of the provisioned Cosmos DB SQL container.')
output cosmosContainerName string = cosmosContainer.name

@description('The Cosmos DB account endpoint to set as the COSMOS_ENDPOINT application setting.')
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint

@description('The name of the standalone Function App that hosts the API (empty when not deployed).')
output functionAppName string = deployFunctionApp ? functionApp!.outputs.functionAppName : ''

@description('The name of the Application Insights component (empty when not deployed).')
output applicationInsightsName string = (deployFunctionApp && deployApplicationInsights) ? applicationInsights.name : ''
