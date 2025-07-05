<#
Synopsis: Copy ASG configuration from one NIC to another.
Description: Useful to manually synchronize security groups between two NICs. Use -Apply to commit changes.
#>

param(
  [Parameter(Mandatory = $true)][string]$sid, #ex: 8197d8ee-bdff-4gba-bvds-bd38sdfvxvf3, subscription id
  [Parameter(Mandatory = $true)][string]$NicSource,
  [Parameter(Mandatory = $true)][string]$NicDest,
  [Parameter(Mandatory = $false)][switch]$Apply
)

$ErrorActionPreference = "Stop"
Set-AzContext -SubscriptionId $sid | Out-Null

$PSNicDest = Get-AzNetworkInterface -name $NicDest
$PSNicSource = Get-AzNetworkInterface -name $NicSource
$ASGs = $PSNicSource.IpConfigurations[0].ApplicationSecurityGroups

Write-Host "Voici les ASG a transferer : " -ForegroundColor Cyan
$ASGs | foreach-object {
  Write-Host ($_.Id).Split('/')[-1]
}

if ($Apply)
{
  $NewNicConfig = Set-AzNetworkInterfaceIpConfig -NetworkInterface $PSNicDest -Name $PSNicDest.IpConfigurations[0].name -ApplicationSecurityGroup $PSNicSource.IpConfigurations[0].ApplicationSecurityGroups
  $NewNicConfig | Set-AzNetworkInterface | Out-Null
  Write-Host "Carte réseau $($PSNicDest.Name) sauvegardée"
}
