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
    $vhub | Add-AzVirtualNetworkSubnetConfig -Name $SNnameHub -AddressPrefix "10.9.9.0/24" | Set-AzVirtualNetwork -verbose
}
if( $(Get-AzVirtualNetworkSubnetConfig -Name $SNnameGW -VirtualNetwork $Vhub -ErrorAction SilentlyContinue).count -eq 0  ) {
    $vhub | Add-AzVirtualNetworkSubnetConfig -Name $SNnameGW -AddressPrefix "10.9.8.0/24"  | Set-AzVirtualNetwork -verbose 
}

# Public IP GW for Hub
$gwpip1 = New-AzPublicIpAddress -Name $GWHubpipName -ResourceGroupName $RG -Location $Location -allocation Static

# On Prem network
$VNetnameOnprem = "VOnprem"
$SNNameOnprem = "SubnetPrem1"
$GWOnprempipName = "Onprem-GW-pip"
$GWOnpremName = "GW-Onprem"
$ConnectionNameHub = "hub-to-Onprem"
$GWIPconfNameOnprem = "GW-ipconf-Onprem"

$VNetOnprem = get-AzVirtualNetwork -name $VNetnameOnprem -ResourceGroupName $RG  -ErrorAction Stop
if( $(Get-AzVirtualNetworkSubnetConfig -Name $SNNameOnprem -VirtualNetwork $VNetOnprem -ErrorAction SilentlyContinue).count -eq 0  ) {
    $VNetOnprem | Add-AzVirtualNetworkSubnetConfig -Name $SNnameHub -AddressPrefix "192.168.1.0/24" | Set-AzVirtualNetwork -verbose
}
if( $(Get-AzVirtualNetworkSubnetConfig -Name $SNnameGW -VirtualNetwork $VNetOnprem -ErrorAction SilentlyContinue).count -eq 0  ) {
    $VNetOnprem | Add-AzVirtualNetworkSubnetConfig -Name $SNnameGW -AddressPrefix "192.168.8.0/24"  | Set-AzVirtualNetwork -verbose 
}

$gwOnprempip = New-AzPublicIpAddress -Name $GWOnprempipName -ResourceGroupName $RG -Location $Location -AllocationMethod Static

#+
# Firewall
#   -
# Get a public IP for the firewall
$FWpip = New-AzPublicIpAddress -Name "fw-pip" -ResourceGroupName $RG  -Location $Location -AllocationMethod Static -Sku Standard
# Create the firewall
$Azfw = New-AzFirewall -Name AzFW01 -ResourceGroupName $RG -Location $Location -VirtualNetworkName $VNetnameHub -PublicIpName $FWpip.Name

#Get the firewall private IP address for future use
$AzfwPrivateIP = $Azfw.IpConfigurations.privateipaddress
$AzfwPrivateIP

$Rule1 = New-AzFirewallNetworkRule -Name "AllowAny" -Protocol Any -SourceAddress "192.168.1.0/24" -DestinationAddress "10.10.0.0/16", "10.11.0.0/16", "10.9.0.0/16" -DestinationPort *

$NetRuleCollection = New-AzFirewallNetworkRuleCollection -Name RCNet01 -Priority 100    -Rule $Rule1 -ActionType "Allow"
$Azfw.NetworkRuleCollections = $NetRuleCollection
Set-AzFirewall -AzureFirewall $Azfw

# VPN for hub VNet

$vnet1 = Get-AzVirtualNetwork -Name $VNetnameHub -ResourceGroupName $RG
$subnet1 = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet1
$gwipconf1 = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfNameHub -Subnet $subnet1 -PublicIpAddress $gwpip1

new-AzVirtualNetworkGateway -Name $GWHubName -ResourceGroupName $RG -Location $Location -IpConfigurations $gwipconf1 -GatewayType Vpn -VpnType RouteBased -GatewaySku VpnGw1

# VPN for OnPrem
$vnet2 = Get-AzVirtualNetwork -Name $VNetnameOnprem -ResourceGroupName $RG
$subnet2 = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet2
$gwipconf2 = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfNameOnprem -Subnet $subnet2 -PublicIpAddress $gwOnprempip

New-AzVirtualNetworkGateway -Name $GWOnpremName -ResourceGroupName $RG -Location $Location -IpConfigurations $gwipconf2 -GatewayType Vpn -VpnType RouteBased -GatewaySku VpnGw1


# Create VPN connections between hub and onprem
$vnetHubgw = Get-AzVirtualNetworkGateway -Name $GWHubName -ResourceGroupName $RG
$vnetOnpremgw = Get-AzVirtualNetworkGateway -Name $GWOnpremName -ResourceGroupName $RG


New-AzVirtualNetworkGatewayConnection -Name $ConnectionNameHub -ResourceGroupName $RG -VirtualNetworkGateway1 $vnetHubgw -VirtualNetworkGateway2 $vnetOnpremgw -Location $Location -ConnectionType Vnet2Vnet -SharedKey $SharedKey
New-AzVirtualNetworkGatewayConnection -Name $ConnectionNameOnprem -ResourceGroupName $RG -VirtualNetworkGateway1 $vnetOnpremgw -VirtualNetworkGateway2 $vnetHubgw -Location $Location -ConnectionType Vnet2Vnet -SharedKey $SharedKey

Get-AzVirtualNetworkGatewayConnection  -ResourceGroupName $RG