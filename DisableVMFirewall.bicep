param vm string = 'VM0VNet0Subnet0'
param location string = resourceGroup().location

resource vmres 'Microsoft.Compute/virtualMachines@2023-03-01' existing =  {
  name: vm  
}


resource MyCmd 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' =  {
  name: 'DisableFw${vm}'
  location: location
  parent: vmres
  properties:{
    source: {
      script: 'netsh advfirewall set allprofiles state off'
      
    }
  }
  
}

output result object = MyCmd
