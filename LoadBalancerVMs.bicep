
param location string = resourceGroup().location

param FrontEndIp string = '10.10.1.9'
param VMS array = [ 'VMA' , 'VMA2 ']

var virtualNetworkName = 'VNetA'
var subnetName = 'SubNetA1'
var loadBalancerName = 'lbvms'
var subnetRef = resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, subnetName)
var FrontEndName = 'VMsFrontEndIp'
var BackendPoolName = concat('VMsIn', virtualNetworkName)

resource loadBalancer 'Microsoft.Network/loadBalancers@2021-05-01' = {
  name: loadBalancerName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: FrontEndName
        properties: {
          privateIPAddress: FrontEndIp
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: subnetRef
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: BackendPoolName
        properties: {
          loadBalancerBackendAddresses: [ 
          ]
        }
         
      }
    ]
    probes: [
      {
        name: 'VMsProbe'
        properties: {
          protocol: 'Tcp'
          port: 3389 
          intervalInSeconds: 60
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'LBRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, FrontEndName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, BackendPoolName)
          }
          protocol: 'Tcp'
          frontendPort: 3389
          backendPort: 3389
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'VMsProbe')
          }
        }
      }
    ]
  }
}
