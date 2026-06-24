// Bicep template to provision an Azure Static Web App for the
// "Strade Aperte" static site (index.html / history.html).
//
// Deploy:
//   az group create --name <rg-name> --location westeurope
//   az deployment group create \
//     --resource-group <rg-name> \
//     --template-file infra/main.bicep \
//     --parameters infra/main.bicepparam

targetScope = 'resourceGroup'

@description('Name of the Static Web App resource.')
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

@description('Pricing tier (SKU) for the Static Web App.')
@allowed([
  'Free'
  'Standard'
])
param sku string = 'Free'

@description('Tags applied to the Static Web App resource.')
param tags object = {
  project: 'strade-aperte'
}

resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
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

@description('The name of the provisioned Static Web App.')
output staticWebAppName string = staticWebApp.name

@description('The default public hostname of the Static Web App.')
output defaultHostname string = staticWebApp.properties.defaultHostname
