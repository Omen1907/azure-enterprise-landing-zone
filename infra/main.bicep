@description('Globally unique lowercase storage account name.')
@minLength(3)
@maxLength(24)
param storageAccountName string = toLower('store${uniqueString(resourceGroup().id)}')

param location string = resourceGroup().location

@description('Log Analytics workspace name.')
param logAnalyticsWorkspaceName string = 'entlzlog-${uniqueString(resourceGroup().id)}'

@secure()
@description('Admin password for the VM')
param adminPassword string

@description('Admin username for the VM')
param adminUsername string = 'azureadmin'

param environment string = 'dev'
param prefix string = 'ent-${environment}'
param tags object = {
  environment: environment
  project: 'enterprise-landing-zone'
}

@description('Your public IP address for RDP (x.x.x.x)')
param adminPublicIp string

param vmCount int = 2

// ====================
// VIRTUAL NETWORK
// ====================

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: '${prefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
}

// ====================
// NSGs
// ====================

resource webNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: '${prefix}-web-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-HTTPS'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-RDP-Admin'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: adminPublicIp
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource appNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: '${prefix}-app-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-From-Web'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8080'
          sourceAddressPrefix: '10.0.1.0/24'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource dbNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: '${prefix}-db-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-From-App'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: '10.0.2.0/24'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ====================
// SUBNETS
// ====================

resource subnetWeb 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  name: '${virtualNetwork.name}/Subnet-web'
  properties: {
    addressPrefix: '10.0.1.0/24'
    networkSecurityGroup: {
      id: webNsg.id
    }
  }
}

resource subnetApp 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  name: '${virtualNetwork.name}/Subnet-app'
  properties: {
    addressPrefix: '10.0.2.0/24'
    networkSecurityGroup: {
      id: appNsg.id
    }
  }
}

resource subnetDB 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  name: '${virtualNetwork.name}/Subnet-db'
  properties: {
    addressPrefix: '10.0.3.0/24'
    networkSecurityGroup: {
      id: dbNsg.id
    }
  }
}

// ====================
// AVAILABILITY SET
// ====================

resource availabilitySet 'Microsoft.Compute/availabilitySets@2024-07-01' = {
  name: '${prefix}-avset'
  location: location
  tags: tags
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 2
  }
  sku: {
    name: 'Aligned'
  }
}

// ====================
// PUBLIC IPS
// ====================

resource publicIps 'Microsoft.Network/publicIPAddresses@2024-07-01' = [for i in range(0, vmCount): {
  name: '${prefix}-pip-${i}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}]

// ====================
// NICs
// ====================

resource nics 'Microsoft.Network/networkInterfaces@2024-07-01' = [for i in range(0, vmCount): {
  name: '${prefix}-nic-${i}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetWeb.id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIps[i].id
          }
        }
      }
    ]
  }
}]

// ====================
// VMs
// ====================

resource vms 'Microsoft.Compute/virtualMachines@2024-07-01' = [for i in range(0, vmCount): {
  name: '${prefix}-vm-${i}'
  location: location
  tags: tags
  properties: {
    availabilitySet: {
      id: availabilitySet.id
    }
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-Datacenter'
        version: 'latest'
      }
      osDisk: {
        name: '${prefix}-osdisk-${i}'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    osProfile: {
      computerName: '${prefix}-vm-${i}'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[i].id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}]

// ====================
// LOG ANALYTICS
// ====================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2024-07-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ====================
// STORAGE
// ====================

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
  }
}

// ====================
// OUTPUTS
// ====================

output vmNames array = [for vm in vms: vm.name]
output publicIpAddresses array = [for pip in publicIps: pip.properties.ipAddress]
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output storageAccountName string = storageAccount.name
