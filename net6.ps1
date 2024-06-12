.\ras -scenario Net1_VNetsABHubRas -Parts @(  "Vnet" , "PrivateDns", "VMs", "Peerings","Routes","DisableFw", "storage" , "Display") -resourcegroup RG -region WestUS
.\ras -scenario Net2_OnPrem -Parts @(  "Vnet" , "VMs", "DisableFw" ,  "Display") -resourcegroup RG -region WestUS
.\HybridFirewall.ps1