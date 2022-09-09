
@description('Azure region to use')
param location string = resourceGroup().location

@description('AKS cluster name')
param aksClusterName string = 'aks${uniqueString(subscription().subscriptionId, resourceGroup().id)}'
@description('AKS username')
param aksAdminUsername string = 'azureuser'
@description('AKS SSH public key')
param aksPublicKey string

resource aksCluster 'Microsoft.ContainerService/managedClusters@2022-06-02-preview' = {
  name: aksClusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksClusterName
    agentPoolProfiles: [
      {
        name: 'agentpool'
        osDiskSizeGB: 0
        count: 2
        vmSize: 'standard_d2s_v3'
        osType: 'Linux'
        mode: 'System'
      }
      {
        name: 'hb120v2'
        count: 0
        vmSize: 'Standard_HB120rs_v2'
        osDiskSizeGB: 128
        osDiskType: 'Ephemeral'
        maxPods: 20
        maxCount: 4
        minCount: 0
        enableAutoScaling: true
        osType: 'Linux'
        mode: 'User'
      }
    ]
    linuxProfile: {
      adminUsername: aksAdminUsername
      ssh: {
        publicKeys: [
          {
            keyData: aksPublicKey
          }
        ]
      }
    }
  }
}

output aksControlPlaneFQDN string = aksCluster.properties.fqdn
output aksClusterName string = aksClusterName

@description('ACR name')
param acrName string = 'acr${uniqueString(subscription().subscriptionId, resourceGroup().id)}'
@description('ACR tier')
param acrSku string = 'Basic'

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: true
  }
}

output acrLoginServer string = containerRegistry.properties.loginServer
output acrName string = acrName

var roleAcrPull = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
resource  assignAcrPullToAks 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, aksClusterName, acrName, 'assignAcrPullToAks')
  scope: containerRegistry
  properties: {
    description: 'Assign AcrPull role to AKS'
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleAcrPull
  }
}
