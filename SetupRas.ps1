Install-WindowsFeature -Name RemoteAccess -IncludeAllSubFeature -IncludeManagementTools
Install-RemoteAccess -VpnType RoutingOnly
$if = (get-netadapter).ifIndex
new-netroute -DestinationPrefix 10.11.0.0/16 -NextHop 10.9.1.1 -InterfaceIndex $if
new-netroute -DestinationPrefix 10.10.0.0/16 -NextHop 10.9.1.1 -InterfaceIndex $if