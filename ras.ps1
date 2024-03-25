[CmdletBinding()]
param (
    [string]$scenario ,

    [Parameter()]
    [string[]]$Parts = @("All") ,
    [string]$ResourceGroup = "RG",
    [string]$Region =  "WestUS"

)

$adminPassword = "LS1Setup!310"
$RG = "$ResourceGroup"
$DNSZone = "azure.luct.fr" 
New-AzResourceGroup -Name "$RG" -Location $Region -force | out-null
$location = (Get-AzResourceGroup -name $rg).location

$scenarios = @{}

 
# $scenario -eq "VNetsABHubRas"
$VNetBName = "VNetB"
$VNetAName = "VNetA"
$VNetHubName = "Hub"

$VNetB = @{
                Vnet = @{ VName = $VNetBName ; Prefix = "10.11." ; Bastion = $true ; SubnetCount = 1 ; SubnetName = "SubnetB" ; RouteTables = $true ; StorageEndpoints = $false } ;
                VMS  = @(  @{ VMname = "VMB" ; VnetName = $VNetBName ; EnabledIpForwarding = $FALSE ; SubnetName = "SubnetB1" ; adminPassword = $adminPassword ; }
                );
                Peerings = @(
                        @{ source = $VNetBName ; destination = "Hub"  ;  allowVirtualNetworkAccess = $true ;  allowForwardedTraffic = $true; useRemoteGateways =  $false ;allowGatewayTransit = $true }
                );
                
                Routes = @( @{ dest = $VNetAName ; subnets =  "SubnetB1" ; NoInternet = $false } )
        }

$VNetA = @{
                Vnet = @{ VName = $VNetAName ; Prefix = "10.10." ; Bastion = $true ; SubnetCount = 2 ; SubnetName = "SubnetA" ; RouteTables = $true ;  StorageEndpoints = $true} ;
                VMS  = @(  
                @{ VMname = "VMA" ; VnetName = $VNetAName ; EnabledIpForwarding = $FALSE ; SubnetName = "SubnetA1" ; adminPassword = $adminPassword },
                @{ VMname = "VMA2" ; VnetName = $VNetAName ; EnabledIpForwarding = $FALSE ; SubnetName = "SubnetA2" ; adminPassword = $adminPassword }
                );
                Peerings = @(
                        @{ source = $VNetAName ; destination = "Hub"  ;  allowVirtualNetworkAccess = $true ;  allowForwardedTraffic = $true; useRemoteGateways =  $false ;allowGatewayTransit = $true }
                );
                Routes = @( @{ dest = $VNetBName ; subnets =  "SubnetA1" ; NoInternet = $true })  
        
        }

$VNetHub = @{
                Vnet = @{ VName = $VNetHubName ; Prefix = "10.9." ; Bastion = $true ; SubnetCount = 1 ; SubnetName = "SubnetHub" ; RouteTables = $false ;  StorageEndpoints = $false  } ;
                VMS  = @(  @{ VMname = "NVA" ; VnetName = $VNetHubName ; EnabledIpForwarding = $true ; SubnetName = "SubnetHub1" ; adminPassword = $adminPassword ; RunScript = ".\SetupRas.ps1"}
                );
                Peerings = @(
                        @{ source = $VNetHubName ; destination = $VNetAName ; allowVirtualNetworkAccess = $true ;  allowForwardedTraffic = $true; useRemoteGateways =  $false ;allowGatewayTransit = $true },
                        @{ source = $VNetHubName ; destination = $VNetBName ; allowVirtualNetworkAccess = $true ;  allowForwardedTraffic = $true; useRemoteGateways =  $false ;allowGatewayTransit = $true }
                );
                Routes = @()
        }
$VNetOnPremName = "VOnprem"
$VNetOnPrem =  @{
        Vnet = @{ VName = $VNetOnPremName ; Prefix = "192.168." ; Bastion = $true ; SubnetCount = 1 ; SubnetName = "SubnetPrem" ; RouteTables = $false ;  StorageEndpoints = $false} ;
        VMS  = @(  
        @{ VMname = "VMONPREM" ; VnetName = $VNetOnPremName ; EnabledIpForwarding = $FALSE ; SubnetName = "SubnetPrem1" ; adminPassword = $adminPassword }
        );
        Peerings = @();
        Routes = @( )  

}


$VNetsVNetsABHubRas = @( $VNetB , $VNetA , $VNetHub);
$VNetOnPremScenario = @( $VNetOnPrem);

$scenarios["Net2_OnPrem"]  = @{
        VNets = $VNetOnPremScenario;
        Parts = {  "Vnet" , "VMs", "DisableFw" ,  "Display"}
        } ; 

$scenarios["Net1_VNetsABHubRas"] = @{
                VNets = $VNetsVNetsABHubRas;
                Parts = {  "Vnet" , "PrivateDns", "VMs", "Peerings","Routes","DisableFw", "storage", "loadbalancervm" , "Display"}
        } ; 
$scenarios["Net1_VNetsVms"] = @{
                VNets = $VNetsVNetsABHubRas;
                Parts = {  "Vnet" , "VMs", "DisableFw", "Display"}
        };

$scenarios["Net1_VNetsVmsPrivateDns"] = @{
                VNets = $VNetsVNetsABHubRas;
                Parts = {  "Vnet" , "VMs", "DisableFw", "PrivateDns" ,  "Display"}
        };
$scenarios["Net1_VNetsVmsPrivateDnsPeerings"] = @{
                VNets = $VNetsVNetsABHubRas;
                Parts = {  "Vnet" , "VMs", "DisableFw",  "PrivateDns" , "Peerings",  "Display"}
        };


$Vnets = $scenarios[$scenario].VNets
if( $Vnets.count  -lt  1 )  {
        write-error "Invalid scenario"
        return  $scenarios  | % { $_.Keys | % { ".\ras -scenario {0} -Parts @({1}) -resourcegroup {3} -region {2} " -f $_, [string]($scenarios[$_].Parts)  , $Region , $ResourceGroup;  }}
}

if( $parts[0] -eq "All" ) {
        $parts = $scenarios[$scenario].Parts;
        Get-AzResourceGroupDeployment  -ResourceGroupName $rg |  % { Remove-AzResourceGroupDeployment -ResourceGroupName $rg -Name $_.DeploymentName }
}

foreach( $part in $parts) {

     write-host -BackgroundColor Blue -ForegroundColor White "Config $scenario scenario , Part $part "
 
# Create VNet
     if( $part -match "VNet"  ) {
        $VNets.Vnet | % { 
                if( $_.routetables) {
                        for( $i = 0 ; $i -lt $_.SubnetCount ; $i++ ) {
                                $RouteTableName = "RT{0}{1}{2}" -f $_.VName, $_.SubnetName , ($i+1);
                                New-AzRouteTable -force -ResourceGroupName $RG -Name $RouteTableName -Location $location;
                        }
                }  
                $vnettemplatename =  ".\VNet2.json";
                if( $_.StorageEndpoints) {
                        $vnettemplatename = ".\VNet2StorageEndPoint.json"
                }
                new-azresourceGroupDeployment -name $("Vnet{0}" -f $_.VName) -ResourceGroupName $RG -TemplateFile $vnettemplatename -TemplateParameterObject $_
        }
        $VNets.VNet | % { (get-AzVirtualNetwork -name $_.VName) }| %{ "{0} {1}" -f $_.Name ,$_.AddressSpace.AddressPrefixes[0]  } 
        $VNets.VNet | % { (get-AzVirtualNetwork -name $_.VName).Subnets }| ft -AutoSize 
     }
     elseif( $part -match "PrivateDns"  ) {
        # Create Azure Private DNS
        new-azresourceGroupDeployment -Name "$DNSZone" -ResourceGroupName  $RG -TemplateFile .\PrivateDns.json -TemplateParameterObject @{DNSZone =$DNSZone ; VNets = @(  $VNets.Vnet.VName ) }
        Get-AzPrivateDnsZone -ResourceGroupName $RG -Name $DnsZone
     }
# Create VMs
     elseif( $part -match "VMs"  ) {
        $VNets.VMS | % { 
                # Create VM
                new-azresourceGroupDeployment -name $_.VMName -ResourceGroupName $RG -TemplateFile .\VM2.json -TemplateParameterObject $_
                $myscript = $_.RunScript
                if(  -not ($myscript-eq $null ))  {
                        if( test-path  $myscript  ) {
                                $myvm =  $_.VMName
                                $a = type $myscript;
                                $cmd = "" ; $a | % { $cmd = $cmd + ";" + $_ }
                                write-host "running script $myscript on $myvm"
                                Invoke-AzVMRunCommand -ResourceGroupName $RG -VMName $myvm -CommandId "RunPowershellScript" -ScriptString $cmd
                        }
                }
        }
     }
# Create VNet Peerings
     elseif( $part -match "Peerings"  ) {
        $VNets.Peerings  | % {
                new-azresourceGroupDeployment -name $( "Peering_{0}To{1}" -f $_.source, $_.destination  ) -ResourceGroupName $RG -TemplateFile .\VNetPeering.json -TemplateParameterObject $_
        }
     }
     elseif( $part -match "Routes"  ) {
        # display NVA
        $NVAIp = (get-azvm -name "NVA" ) | % { $_.NetworkProfile.NetworkInterfaces[0].Id  | Get-AzNetworkInterface } | % {   $_.IpConfigurations.PrivateIpAddress }
        "NVA IP $NVAIP"

        # Create Routes
        $Vnets | % {
                $vnet = $_.Vnet.VName
                foreach ( $route in $_.Routes ) {
                        $dest = $Route.dest
                        $subnet = $Route.subnets;
                        $RouteTableName = "RT{0}{1}" -f $vnet , $subnet;
                        write-host "Working on routetable  name : $RouteTableName";
                        $routetable = Get-AzRouteTable -Name $RouteTableName -ResourceGroupName $RG 
                        $RouteName = "To"+ $dest;
                        $addressprefix = ( Get-AzVirtualNetwork -ResourceGroupName $RG -Name $dest).AddressSpace.AddressPrefixes[0];
                        $nextHopIpAddress = $NVAIp;
                        $nextHopType = "VirtualAppliance";
                        Add-AzRouteConfig -Name $RouteName  -RouteTable $routetable -AddressPrefix $addressprefix -NextHopIpAddress  $nextHopIpAddress -NextHopType $nextHopType
                        if( $route.NoInternet ) {
                                $RouteName = "NoInternet";
                                Add-AzRouteConfig -Name $RouteName -RouteTable $routetable -AddressPrefix "0.0.0.0/0" -NextHopType None
                        }
                        Set-AzRouteTable -RouteTable $routetable
                        (Get-AzRouteTable -Name $RouteTableName -ResourceGroupName $RG).Routes
                }              
        }
    }
                
# disable firewall on VMS
        elseif( $part -match "DisableFw"  ) {
                $VNets.VMS | % { 
                        # Disable Firewall
                        new-azresourceGroupDeployment -name $("DisableFW{0}" -f $_.VMName ) -ResourceGroupName $RG -TemplateFile .\DisableVMFirewall.json -TemplateParameterObject @{ vmname = $_.VMName 
                        }       
                }
        }
        elseif( $part -match "Display"  ) {
                Get-AzVirtualNetwork -ResourceGroupName $RG | % { "VNet {0} {1}" -f $_.Name , $_.AddressSpace.AddressPrefixes[0]}
                (Get-AzVirtualNetwork -ResourceGroupName $RG).Subnets.RouteTable
                (Get-AzVirtualNetwork -ResourceGroupName $RG).Subnets
                get-azvm -ResourceGroupName $rg | Format-Table -AutoSize
                Get-AzNetworkInterface -ResourceGroupName $rg | Format-Table -AutoSize
                get-azvm -ResourceGroupName $rg  | % { $_.NetworkProfile.NetworkInterfaces[0].Id  | Get-AzNetworkInterface} | % {  $_.Name + " " +  $_.IpConfigurations.PrivateIpAddress }
                
                $NVAIp = (get-azvm -name "NVA" -ErrorAction SilentlyContinue ) | % { $_.NetworkProfile.NetworkInterfaces[0].Id  | Get-AzNetworkInterface } | % {   $_.IpConfigurations.PrivateIpAddress }
                "NVA IP $NVAIP"
                $(Get-AzVirtualNetwork -ResourceGroupName $rg).Name | % { Get-AzVirtualNetworkPeering -VirtualNetworkName $_ -ResourceGroupName $RG }
                write-warning "Please setup RAS on NVA and configure lan routing for Spokes"
                # display Peering info
                $(Get-AzVirtualNetwork -ResourceGroupName $rg).Name | % { Get-AzVirtualNetworkPeering -VirtualNetworkName $_ -ResourceGroupName $RG }

        }
        elseif ( $part -match "storage" ) {
                $storagename =  "luctstorage";
                $containername = "test"
                new-azresourceGroupDeployment -ResourceGroupName $RG -TemplateFile .\luctstorage.json -TemplateParameterObject @{ storageAccounts_luctstorage_name = $storagename }
                $storage = (Get-AzStorageAccount -StorageAccountName  $storagename  -ResourceGroupName $RG)
                $Blobpath = $storage.PrimaryEndpoints.Blob
                $Blobpath 
                if( $Blobpath -ne $null ) {
                        Set-AzStorageBlobContent -File '.\emmerdes.png' -Blob $BlobName -Container  $containername -Context $storage.Context
                }
        }
}



