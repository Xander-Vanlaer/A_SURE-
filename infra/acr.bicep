// acr.bicep
// Creates an Azure Container Registry (ACR) to store our Docker image.
// Also creates a least-privilege pull token so ACI can pull the image securely.

// Use the same location as the resource group
param location string = resourceGroup().location

// ACR name must be globally unique across all of Azure.
// uniqueString generates a deterministic hash from the resource group ID.
param acrName string = 'crudacr${uniqueString(resourceGroup().id)}'

// The container registry itself — Basic SKU is the cheapest tier, fine for this assignment
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    // Best practice: disable admin user and use tokens instead for access control
    adminUserEnabled: false
  }
}

// Scope map defines what actions the token is allowed to perform.
// We only grant read access (pull) — this is the least privilege principle.
resource scopeMap 'Microsoft.ContainerRegistry/registries/scopeMaps@2023-01-01-preview' = {
  name: 'pull-only-scope'
  parent: acr
  properties: {
    actions: [
      'repositories/*/content/read'   // allows pulling image layers
      'repositories/*/metadata/read'  // allows reading image tags and metadata
    ]
  }
}

// The actual token that ACI will use to authenticate with ACR.
// It is linked to the scope map above so it can only pull, not push or delete.
resource acrToken 'Microsoft.ContainerRegistry/registries/tokens@2023-01-01-preview' = {
  name: 'pull-token'
  parent: acr
  properties: {
    scopeMapId: scopeMap.id
    status: 'enabled'
  }
}

// Output the login server URL (e.g. crudacr1234.azurecr.io) for use in main.bicep
output acrLoginServer string = acr.properties.loginServer

// Output the ACR name so we can reference it in CLI commands
output acrName string = acr.name