param storageAccountName string
param logAnalyticsWorkspaceName string
@secure()
param adminPassword string
param adminUsername string
param environment string
param prefix string
param tags object
param adminPublicIp string
param adminObjectId string
param securityGroupObjectId string
param vmCount int
param location string = resourceGroup().location

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
// RBAC
// ====================

resource adminRbac 'Microsoft.Authorization/roleAssignments@2024-04-01-preview' = {
  name: guid(resourceGroup().id, 'admin-owner')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
    )
    principalId: 'adminObjectId'
    principalType: 'User'
  }
}

resource securityRbac 'Microsoft.Authorization/roleAssignments@2024-04-01-preview' = {
  name: guid(resourceGroup().id, 'security-reader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'acdd72a7-3385-48ef-bd42-f606fba81ae7'
    )
    principalId: 'securityGroupObjectId'
    principalType: 'Group'
  }
}

// ====================
// Policies
// ====================

resource requireEnvironmentTag 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: '${prefix}-require-env-tag'
  scope: resourceGroup()
  properties: {
    displayName: 'Require Environment Tag'
    description: 'Ensure all resources have the Environment tag'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/require-a-tag-on-resources'
    parameters: {
      tagName: {
        value: 'Environment'
      }
    }
  }
}

resource allowedLocationsPolicy 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: '${prefix}-allowed-locations'
  scope: resourceGroup()
  properties: {
    displayName: 'Allowed Locations'
    description: 'Restrict resources to allowed regions'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/allowed-locations'
    parameters: {
      listOfAllowedLocations: {
        value: [
          'eastus'
          'westeurope'
        ]
      }
    }
  }
}

// ====================
// Monitor agent
// ====================

resource monitorAgent 'Microsoft.HybridCompute/machines/extensions@2024-07-01' = [
  for i in range(0, vmCount): {
    name: '${vms[i].name}/AzureMonitorAgent'
    location: location
    properties: {
      publisher: 'Microsoft.Azure.Monitor'
      type: 'AzureMonitorWindowsAgent'
      typeHandlerVersion: '1.0'
      autoUpgradeMinorVersion: true
      settings: {
        workspaceId: logAnalyticsWorkspace.properties.customerId
      }
    }
    dependsOn: [
      vms[i]
      logAnalyticsWorkspace
    ]
  }
]

// ====================
// OUTPUTS
// ====================

output vmNames array = [for vm in vms: vm.name]
output publicIpAddresses array = [for pip in publicIps: pip.properties.ipAddress]
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output storageAccountName string = storageAccount.name
