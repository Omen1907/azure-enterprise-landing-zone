@description('Globally unique lowercase storage account name.')
@minLength(3)
@maxLength(24)
param storageAccountName string = toLower('store${uniqueString(resourceGroup().id)}')
param location string = resourceGroup().location
@description('Log Analytics workspace name.')
param logAnalyticsWorkspaceName string = 'entLZLog-${uniqueString(resourceGroup().id)}'
@secure()
@description('Admin password for the VM')
param adminPassword string
@description('Admin username for the VM')
param adminUsername string = 'azureadmin'
param environment string = 'dev'
param prefix string
param tags object
param vmCount int = 2

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: 'ent-${environment}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
}

param adminPublicIp string

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
          sourceAddressPrefix: '10.0.1.0/24' // Web subnet
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
        }
      }
    ]
  }
}]

resource vms 'Microsoft.Compute/virtualMachines@2024-07-01' = [for i in range(0, vmCount): {
  name: '${prefix}-vm-${i}'
  location: location
  tags: tags
  properties: {
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
        diskSizeGB: 127
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

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2024-07-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

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
    publicNetworkAccess: 'Enabled'
    allowSharedKeyAccess: false
  }
}

resource vmExtensions 'Microsoft.Compute/virtualMachines/extensions@2024-01-01' = [for i in range(0, vmCount): {
  name: '${vms[i].name}/AzureMonitorWindowsAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
  }
}]

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2024-01-01' = {
  name: '${prefix}-dcr'
  location: location
  tags: tags
  properties: {
    destinations: {
      logAnalytics: [
        {
          name: 'la-destination'
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Event'
        ]
        destinations: [
          'la-destination'
        ]
      }
    ]
    dataSources: {
      windowsEventLogs: [
        {
          name: 'eventLogs'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            'System!*'
          ]
        }
      ]
    }
  }
}

resource dcrAssociations 'Microsoft.Insights/dataCollectionRuleAssociations@2024-01-01' = [for i in range(0, vmCount): {
  name: '${vms[i].name}-association'
  scope: vms[i]
  properties: {
    dataCollectionRuleId: dataCollectionRule.id
  }
}]

output vmNames array = [for vm in vms: vm.name]
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output storageAccountName string = storageAccount.name
