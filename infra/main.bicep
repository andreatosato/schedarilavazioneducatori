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
param name string = 'black-sand-00abc5803'

@description('Location for the Cosmos DB account. Defaults to the resource group location.')
param cosmosLocation string = resourceGroup().location

@description('Enable the Cosmos DB lifetime Free Tier (1000 RU/s throughput and 25 GB storage free). Only one free-tier account is allowed per subscription, so set this to false if the subscription already has one.')
param enableCosmosFreeTier bool = true

@description('Name of the existing Static Web App whose application settings receive the Cosmos DB connection string. Defaults to the base name.')
param staticWebAppName string = name

@description('When true, sets the Cosmos DB application setting on the Static Web App so the Azure Functions API can reach Cosmos DB. Set to false if the Static Web App does not exist yet.')
param configureStaticWebAppSettings bool = true

@description('When true, grants the Static Web App system-assigned managed identity the Cosmos DB Built-in Data Contributor role so the API can use Microsoft Entra ID (AAD) authentication. Requires the system-assigned identity to be enabled on the Static Web App.')
param assignCosmosDataRole bool = true

@description('Tags applied to every resource.')
param tags object = {
  project: 'strade-aperte'
}

var cosmosAccountName = toLower('${name}-cosmos')
var cosmosDatabaseName = 'schede'
var cosmosContainerName = 'schede'

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: cosmosAccountName
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
resource staticWebApp 'Microsoft.Web/staticSites@2024-04-01' existing = if (configureStaticWebAppSettings || assignCosmosDataRole) {
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

resource cosmosDataRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = if (assignCosmosDataRole) {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, staticWebAppName, '00000000-0000-0000-0000-000000000002')
  properties: {
    roleDefinitionId: cosmosDataContributorRoleId
    principalId: staticWebApp.identity.principalId
    scope: cosmosAccount.id
  }
}

@description('The name of the provisioned Cosmos DB account.')
output cosmosAccountName string = cosmosAccount.name

@description('The name of the provisioned Cosmos DB SQL database.')
output cosmosDatabaseName string = cosmosDatabase.name

@description('The name of the provisioned Cosmos DB SQL container.')
output cosmosContainerName string = cosmosContainer.name

@description('The Cosmos DB account endpoint to set as the COSMOS_ENDPOINT application setting.')
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
