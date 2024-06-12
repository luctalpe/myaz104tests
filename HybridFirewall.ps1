$RG = "RG"     # idea from https://learn.microsoft.com/en-us/azure/firewall/tutorial-hybrid-ps
$Location = "West US"
$SharedKey = 'Thi67qsis_56!AWb23'



#
# Hub :
#   - Subnets : Firewall , Gateway
#   - Public Ip for gw
#
$VNetnameHub = "Hub"
$SNnameHub = "AzureFirewallSubnet"
$SNnameGW = "GatewaySubnet"
$GWHubpipName = "Hub-GW-pip"
$GWHubName = "GW-hub"
$GWIPconfNameHub = "GW-ipconf-hub"


$Vhub = get-AzVirtualNetwork -name $VNetnameHub -ResourceGroupName $RG  -ErrorAction Stop


if( $(Get-AzVirtualNetworkSubnetConfig -Name $SNnameHub -VirtualNetwork $Vhub -ErrorAction SilentlyContinue).count -eq 0  ) {
    write-host -ForegroundColor White -BackgroundColor red "Adding $SNnameHub subnet to $VNetnameHub "
    $vhub | Add-AzVirtualNetworkSubnetConfig -Name $SNnameHub -AddressPrefix "10.9.9.0/24" | Set-AzVirtualNetwork -verbose
}
if( $(Get-AzVirtualNetworkSubnetConfig -Name $SNnameGW -VirtualNetwork $Vhub -ErrorAction SilentlyContinue).count -eq 0  ) {
    write-host -ForegroundColor White -BackgroundColor red "Adding $SNnameGW subnet to $VNetnameHub "
    $vhub | Add-AzVirtualNetworkSubnetConfig -Name $SNnameGW -AddressPrefix "10.9.8.0/24"  | Set-AzVirtualNetwork -verbose 
}

# Public IP GW for Hub
$gwpip1 = New-AzPublicIpAddress -Name $GWHubpipName -ResourceGroupName $RG -Location $Location -allocation Static

# On Prem network
$VNetnameOnprem = "VOnprem"
$SNNameOnprem = "SubnetPrem1"
$GWOnprempipName = "Onprem-GW-pip"
$GWOnpremName = "GW-Onprem"

$GWIPconfNameOnprem = "GW-ipconf-Onprem"
$ConnectionNameOnprem = "OnPrem-to-Hub"

$VNetOnprem = get-AzVirtualNetwork -name $VNetnameOnprem -ResourceGroupName $RG  -ErrorAction Stop
if( $(Get-AzVirtualNetworkSubnetConfig -Name $SNNameOnprem -VirtualNetwork $VNetOnprem -ErrorAction SilentlyContinue).count -eq 0  ) {
    write-host -ForegroundColor White -BackgroundColor red "Adding $SNnameHub subnet to $VNetnameOnprem "
    $VNetOnprem | Add-AzVirtualNetworkSubnetConfig -Name $SNnameHub -AddressPrefix "192.168.1.0/24" | Set-AzVirtualNetwork -verbose
}
if( $(Get-AzVirtualNetworkSubnetConfig -Name $SNnameGW -VirtualNetwork $VNetOnprem -ErrorAction SilentlyContinue).count -eq 0  ) {
    write-host -ForegroundColor White -BackgroundColor red "Adding  $SNnameGW subnet to $VNetnameOnprem "
    $VNetOnprem | Add-AzVirtualNetworkSubnetConfig -Name $SNnameGW -AddressPrefix "192.168.8.0/24"  | Set-AzVirtualNetwork -verbose 
}


# Routes for OnPrem network
$onPremRouteTable = New-AzRouteTable -Name "RTOnPrem" -ResourceGroupName $RG -Location $Location 

write-host -ForegroundColor White -BackgroundColor red "Creating a Route table for OnPrem to access Hub Azure and spokes vnets"
Add-AzRouteConfig -Name "ToHubAndSpokes"  -RouteTable $onPremRouteTable -AddressPrefix "10.0.0.0/8"  -NextHopType VirtualNetworkGateway 
Set-AzRouteTable -RouteTable $onPremRouteTable   
Get-AzRouteTable -Name   "RTOnPrem" -ResourceGroupName $RG             

$vonprem = Get-AzVirtualNetwork -name "VOnprem"
$subnetconfig = ( Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vonprem).Where( { $_.Name -eq "SubnetPrem1"})
Set-AzVirtualNetworkSubnetConfig -Name "Subnetprem1" -VirtualNetwork $vonprem -AddressPrefix $subnetconfig.AddressPrefix -RouteTable $onPremRouteTable
$vonprem |  Set-AzVirtualNetwork



$gwOnprempip = New-AzPublicIpAddress -Name $GWOnprempipName -ResourceGroupName $RG -Location $Location -AllocationMethod Static

#+
# Firewall
#   -
# Get a public IP for the firewall
# $FWpip = New-AzPublicIpAddress -Name "fw-pip" -ResourceGroupName $RG  -Location $Location -AllocationMethod Static -Sku Standard
# Create the firewall

write-host -ForegroundColor White -BackgroundColor red "Creating Firewall AzFW01 in $VNetnameHub"
$Azfw = get-azfirewall -name "AzFw01"
if( $Azfw -eq $null ) {
    $Azfw = New-AzFirewall -Name AzFW01 -ResourceGroupName $RG -Location $Location -VirtualNetworkName $VNetnameHub  # -PublicIpName $FWpip.Name
    write-host -ForegroundColor White -BackgroundColor red "fw-pip Firewall Private  Ip address $AzfwPrivateIP"

    $Rule1 = New-AzFirewallNetworkRule -Name "AllowAny" -Protocol Any -SourceAddress "192.168.1.0/24", "10.0.0.0/8" -DestinationAddress "192.168.1.0/24", "10.0.0.0/8" -DestinationPort *

    $NetRuleCollection = New-AzFirewallNetworkRuleCollection -Name RCNet01 -Priority 100    -Rule $Rule1 -ActionType "Allow"
    $Azfw.NetworkRuleCollections = $NetRuleCollection
    write-host -ForegroundColor White -BackgroundColor red "Adding Network Rule to allow everything between 192.168.1.0/24 and 10.0.0.0/8" 
    Set-AzFirewall -AzureFirewall $Azfw
}

#Get the firewall private IP address for future use
$AzfwPrivateIP = $Azfw.IpConfigurations.privateipaddress


# Add  route to OnPrem for Spokes route tables
$NVAIp = (get-azvm -name "NVA" ) | % { $_.NetworkProfile.NetworkInterfaces[0].Id  | Get-AzNetworkInterface } | % {   $_.IpConfigurations.PrivateIpAddress }
$RTAzure = New-AzRouteTable -Name "RTAzure" -ResourceGroupName $RG -Location $Location 
write-host -ForegroundColor White -BackgroundColor red "Creating a Route table RTAzure for Azure to spokes and OnPrem"
Add-AzRouteConfig -Name "ToHubRasAppliance"  -RouteTable $RTAzure -AddressPrefix "10.0.0.0/8"  -NextHopType VirtualAppliance -NextHopIpAddress $NVAIp
Add-AzRouteConfig -Name "ToFirewall"  -RouteTable $RTAzure -AddressPrefix "192.168.1.0/24"  -NextHopType VirtualAppliance -NextHopIpAddress $AzfwPrivateIP
Set-AzRouteTable -RouteTable $RTAzure  

foreach ( $vnetname in ("VnetA" , "VNetB" , "Hub") ) {
    $vnet = Get-AzVirtualNetwork -name $vnetname
    $subnetconfigs  = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet
    foreach ($subnetconfig in $subnetconfigs) {
        if( $subnetconfig.Name -match "^Subnet" ) {
            Set-AzVirtualNetworkSubnetConfig -Name  $subnetconfig.Name -VirtualNetwork $vnet -AddressPrefix $subnetconfig.AddressPrefix -RouteTable $RTAzure  
        }
    }
    $vnet | Set-AzVirtualNetwork
}

$RTGWAzure = New-AzRouteTable -Name "RTGWAzure" -ResourceGroupName $RG -Location $Location 
write-host -ForegroundColor White -BackgroundColor red "Creating a Route table RTGWAzure to route  inbound gateway traffic to Firewall"
Add-AzRouteConfig -Name "ToFirewall"  -RouteTable $RTGWAzure -AddressPrefix "192.168.1.0/24"  -NextHopType VirtualAppliance -NextHopIpAddress $AzfwPrivateIP
$vnethub = Get-AzVirtualNetwork -name "Hub"
$subnetconfig = Get-AzVirtualNetworkSubnetConfig -Name "AzureFirewallSubnet" -VirtualNetwork $vnethub
Set-AzVirtualNetworkSubnetConfig -Name  $subnetconfig.Name -VirtualNetwork $vnethub -AddressPrefix $subnetconfig.AddressPrefix -RouteTable $RTGWAzure
$vnetub |  Set-AzVirtualNetwork 


# VPN for hub VNet

$vnet1 = Get-AzVirtualNetwork -Name $VNetnameHub -ResourceGroupName $RG
$subnet1 = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet1
$gwipconf1 = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfNameHub -Subnet $subnet1 -PublicIpAddress $gwpip1

write-host -ForegroundColor White -BackgroundColor red "Creating VPN GW $GWHubName "
new-AzVirtualNetworkGateway -Name $GWHubName -ResourceGroupName $RG -Location $Location -IpConfigurations $gwipconf1 -GatewayType Vpn -VpnType RouteBased -GatewaySku VpnGw1

# VPN for OnPrem
$vnet2 = Get-AzVirtualNetwork -Name $VNetnameOnprem -ResourceGroupName $RG
$subnet2 = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet2
$gwipconf2 = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfNameOnprem -Subnet $subnet2 -PublicIpAddress $gwOnprempip

write-host -ForegroundColor White -BackgroundColor red "Creating VPN GW $GWOnpremName"
New-AzVirtualNetworkGateway -Name $GWOnpremName -ResourceGroupName $RG -Location $Location -IpConfigurations $gwipconf2 -GatewayType Vpn -VpnType RouteBased -GatewaySku VpnGw1

# Create VPN connections between hub and onprem
$vnetHubgw = Get-AzVirtualNetworkGateway -Name "GW-hub" -ResourceGroupName $RG
$vnetOnpremgw = Get-AzVirtualNetworkGateway -Name "Gw-OnPrem" -ResourceGroupName $RG

write-host -ForegroundColor White -BackgroundColor red "Creating VPN GW connection between GW-hub and Gw-OnPrem"
New-AzVirtualNetworkGatewayConnection -Name "hub-to-Onprem" -ResourceGroupName $RG -VirtualNetworkGateway1 $vnetHubgw -VirtualNetworkGateway2 $vnetOnpremgw -Location $Location -ConnectionType Vnet2Vnet -SharedKey $SharedKey
write-host -ForegroundColor White -BackgroundColor red "Creating VPN GW connection between Gw-OnPrem and GW-hub. Please check connection status"
New-AzVirtualNetworkGatewayConnection -Name "OnPrem-to-Hub" -ResourceGroupName $RG -VirtualNetworkGateway1 $vnetOnpremgw -VirtualNetworkGateway2 $vnetHubgw -Location $Location -ConnectionType Vnet2Vnet -SharedKey $SharedKey

Get-AzVirtualNetworkGatewayConnection  -ResourceGroupName $RG

