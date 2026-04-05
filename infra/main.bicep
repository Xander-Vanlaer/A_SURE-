// main.bicep
// Deploys the full infrastructure for the CRUD app:
//   - Log Analytics workspace (Azure Monitor for container logs)
//   - Network Security Group (firewall: only port 80 allowed in)
//   - Virtual Network + Subnet (dedicated network for the app)
//   - Azure Container Instance (runs the CRUD app container)

// Use the same location as the resource group
param location string = resourceGroup().location

// The ACR login server URL — passed in at deploy time (e.g. crudacr1234.azurecr.io)
param acrLoginServer string

// The pull token password generated from acr.bicep — marked @secure() so Azure
// never logs it or shows it in deployment history
@secure()
param acrTokenPassword string

// --- Log Analytics Workspace ---
// This is required to send container logs to Azure Monitor.
// The container group references this workspace in its diagnostics section.
resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'crud-log-workspace'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }  // pay-per-GB pricing, cheapest option
    retentionInDays: 30          // keep logs for 30 days
  }
}

// --- Network Security Group (NSG) ---
// Acts as a firewall for the subnet.
// Only allows inbound HTTP traffic on port 80.
// All other inbound traffic is explicitly denied.
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'crud-nsg'
  location: location
  properties: {
    securityRules: [
      {
        // Rule 1: allow HTTP in from any source on port 80
        // Priority 100 — evaluated before the deny-all rule below
        name: 'allow-http-inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        // Rule 2: deny all other inbound traffic
        // Priority 200 — lower priority means it is checked after rule 1
        // This ensures only required traffic flows in (best practice)
        name: 'deny-all-inbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// --- Virtual Network + Subnet ---
// Creates a dedicated VNet for the app as required by the assignment.
// The subnet has the NSG attached and an ACI delegation so Azure
// knows this subnet is reserved for Container Instances.
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'crud-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']  // full address range for the VNet
    }
    subnets: [
      {
        name: 'crud-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'              // subset of the VNet range
          networkSecurityGroup: { id: nsg.id }       // attach the NSG as firewall
          delegations: [
            {
              // ACI delegation — required so Azure Container Instances
              // can deploy into this subnet
              name: 'aci-delegation'
              properties: {
                serviceName: 'Microsoft.ContainerInstance/containerGroups'
              }
            }
          ]
        }
      }
    ]
  }
}

// --- Azure Container Instance ---
// Runs the CRUD app container with a public IP on port 80.
// Pulls the image from ACR using the least-privilege pull token.
// Sends all container logs to the Log Analytics workspace above.
// Note: Azure does not support assigning a public IP to an ACI that is
// directly attached to a VNet subnet, so subnetIds is omitted here.
// The VNet and NSG are still created and the dependsOn ensures they
// are provisioned before the container group.
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: 'crud-container-group'
  location: location
  properties: {
    osType: 'Linux'

    // Public IP with port 80 open so the app is reachable from a browser
    ipAddress: {
      type: 'Public'
      ports: [{ protocol: 'TCP', port: 80 }]
    }

    // Credentials to pull the image from ACR.
    // Uses the least-privilege pull-token instead of admin credentials.
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        username: 'pull-token'
        password: acrTokenPassword
      }
    ]

    // Send container stdout/stderr logs to Azure Monitor via Log Analytics
    diagnostics: {
      logAnalytics: {
        workspaceId: logWorkspace.properties.customerId
        workspaceKey: logWorkspace.listKeys().primarySharedKey
      }
    }

    // Container definition
    containers: [
      {
        name: 'crud-app'
        properties: {
          image: '${acrLoginServer}/crud-app:latest'  // image from our ACR
          ports: [{ port: 80, protocol: 'TCP' }]
          resources: {
            requests: {
              // Minimal resources to save Azure credits
              cpu: json('0.5')
              memoryInGB: json('1.0')
            }
          }
        }
      }
    ]
  }
  // Ensure VNet and NSG are created before the container group
  dependsOn: [vnet]
}

// Output the public IP address after deployment so we can open it in the browser
output publicIp string = containerGroup.properties.ipAddress.ip