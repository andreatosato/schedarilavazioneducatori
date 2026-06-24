// Bicep template that provisions ALL the Azure infrastructure for the
// "Strade Aperte" app, end to end:
//   * Azure Static Web App (Free plan) that hosts the static site.
//   * Azure Cosmos DB for NoSQL (Free Tier) that stores the schede.
//   * A Static Web Apps "database connection" that exposes Cosmos DB
//     through the built-in Data API Builder (GraphQL at /data-api/graphql),
//     so the frontend can persist records without any custom server code.
//
// Everything is created automatically by a single deployment, e.g.:
//   az group create --name <rg-name> --location westeurope
//   az deployment group create \
//     --resource-group <rg-name> \
//     --template-file infra/main.bicep \
//     --parameters infra/main.bicepparam

targetScope = 'resourceGroup'

@description('Base name used to derive the resource names.')
param name string = 'schedari-strade-aperte'

@description('Location for the Static Web App. Only a subset of regions support Static Web Apps.')
@allowed([
  'westeurope'
  'northeurope'
  'eastus2'
  'centralus'
  'westus2'
  'eastasia'
])
param location string = 'westeurope'

@description('Location for the Cosmos DB account. Defaults to the resource group location.')
param cosmosLocation string = resourceGroup().location

@description('Pricing tier (SKU) for the Static Web App.')
@allowed([
  'Free'
  'Standard'
])
param sku string = 'Free'

@description('Enable the Cosmos DB lifetime Free Tier (1000 RU/s throughput and 25 GB storage free). Only one free-tier account is allowed per subscription, so set this to false if the subscription already has one.')
param enableCosmosFreeTier bool = true

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

resource staticWebApp 'Microsoft.Web/staticSites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    // The app content is published from CI using the deployment token,
    // so no source-control provider is configured on the resource itself.
    allowConfigFileUpdates: true
    stagingEnvironmentPolicy: 'Enabled'
  }
}

// Links the Cosmos DB account to the Static Web App. The platform reads the
// Data API Builder config from the `swa-db-connections` folder in the repo and
// serves the database at /data-api/graphql. The connection string is injected
// as the DATABASE_CONNECTION_STRING value the config references.
resource databaseConnection 'Microsoft.Web/staticSites/databaseConnections@2024-04-01' = {
  parent: staticWebApp
  name: 'default'
  properties: {
    resourceId: cosmosAccount.id
    region: cosmosLocation
    connectionString: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
  }
}

@description('The name of the provisioned Static Web App.')
output staticWebAppName string = staticWebApp.name

@description('The default public hostname of the Static Web App.')
output defaultHostname string = staticWebApp.properties.defaultHostname

@description('The full public URL of the app.')
output appUrl string = 'https://${staticWebApp.properties.defaultHostname}'

@description('The name of the provisioned Cosmos DB account.')
output cosmosAccountName string = cosmosAccount.name
