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

@description('The name of the provisioned Cosmos DB account.')
output cosmosAccountName string = cosmosAccount.name

@description('The name of the provisioned Cosmos DB SQL database.')
output cosmosDatabaseName string = cosmosDatabase.name

@description('The name of the provisioned Cosmos DB SQL container.')
output cosmosContainerName string = cosmosContainer.name
