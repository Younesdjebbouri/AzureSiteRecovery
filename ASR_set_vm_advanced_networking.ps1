<#
Synopsis: Configure advanced network settings for failover and test failover.
Description: Sets subnets, network security groups and optional accelerated networking for the replicated VM.
#>

# Set failover and test failover network settings

param(
  [Parameter(Mandatory = $true)][string]$vmName, # "vm-test-1"
  [Parameter(Mandatory = $true)][string]$resourceGroupSourceName, # "RG-TRO2"
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultName, # "rsv1"
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultResourceGroupName, # "RG-TRO2-rsv"
  [Parameter(Mandatory = $true)][string]$asrFabricName, # "test-francecentral-fabric"
  [Parameter(Mandatory = $true)][string]$asrProtectionContainer, # "test-1-fc-source-container"
  [Parameter(Mandatory = $true)][string]$recoveryVnetName, # "RG-TRO2-vnet"
  [Parameter(Mandatory = $true)][string]$recoveryVnetResourceGroupName, # "RG-TRO2"
  [Parameter(Mandatory = $true)][string]$recoveryVnetSubnetName, # "default"
  [Parameter(Mandatory = $true)][string]$testNetworkName, # "vn-test-1"
  [Parameter(Mandatory = $true)][string]$testNetworkResourceGroupName, # "RG-TRO2"
  [Parameter(Mandatory = $true)][string]$testSubnetName, # "sub-test-1"
  [Parameter(Mandatory = $true)][string]$testNetworkSecurityGroupName # "nsg-app-test-failover"
)

$ErrorActionPreference = "Stop"

$vault = Get-AzRecoveryServicesVault -Name $recoveryServiceVaultName -ResourceGroupName $recoveryServiceVaultResourceGroupName
Set-AzRecoveryServicesAsrVaultContext -Vault $vault -WarningAction SilentlyContinue | Out-Null
$Fabric = Get-AzRecoveryServicesAsrFabric -Name $asrFabricName
$ProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $Fabric -Name $asrProtectionContainer

$RPI = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $ProtContainer -FriendlyName $vmName
if ($RPI.ProtectionState -ne "Protected")
{
  Write-Warning "VM not protected yet, stopping"
  Exit
}

$vm = Get-AzVM -ResourceGroupName $resourceGroupSourceName -Name $vmName

# Update protected item settings:
# https://learn.microsoft.com/en-us/powershell/module/az.recoveryservices/new-azrecoveryservicesasrreplicationprotecteditem?view=azps-10.1.0
# https://learn.microsoft.com/en-us/powershell/module/az.recoveryservices/set-azrecoveryservicesasrreplicationprotecteditem?view=azps-10.1.0
# https://learn.microsoft.com/en-us/powershell/module/az.recoveryservices/new-azrecoveryservicesasrvmnicconfig?view=azps-10.1.0
# https://learn.microsoft.com/en-us/powershell/module/az.recoveryservices/new-azrecoveryservicesasrvmnicipconfig?view=azps-10.1.0

$RecoveryVnet = Get-AzVirtualNetwork -Name $recoveryVnetName -ResourceGroupName $recoveryVnetResourceGroupName
$TestVnet = Get-AzVirtualNetwork -Name $testNetworkName -ResourceGroupName $testNetworkResourceGroupName

# Not enough: unable to set:
#   - test failover network security group (-TfoNetworkSecurityGroupId)
#   - accelerated networking on test failover nic (-EnableAcceleratedNetworkingOnTfo)
# Set-AzRecoveryServicesAsrReplicationProtectedItem -InputObject $RPI `
#   -RecoveryNetworkSecurityGroupId $RecoveryNetworkSecurityGroupId `
#   -EnableAcceleratedNetworkingOnRecovery `
#   -TestNetworkId $TestVnet.Id `
#   -TestNicSubnetName $testSubnetName `
#   -RecoveryVirtualMachineScaleSetId $vmss2.Id #`
#   #-RecoveryLBBackendAddressPoolId $lbbap.Id TODO

$nicConfigs = @()
foreach($nicid in $vm.NetworkProfile.NetworkInterfaces.Id)
{
  $nic = Get-AzNetworkInterface -ResourceId $nicid

  $FirstIPConfig = $nic.IpConfigurations[0]
  $RecoveryNetworkSecurityGroupId = $nic.NetworkSecurityGroup.Id # Same as source
  $TfoNetworkSecurityGroupId = (Get-AzNetworkSecurityGroup -Name $testNetworkSecurityGroupName -ResourceGroupName $recoveryServiceVaultResourceGroupName).Id

  $LoadBalancerBackendAddressPools = $FirstIPConfig.LoadBalancerBackendAddressPools
  $extraArgs = @{}
  if ($LoadBalancerBackendAddressPools.Count -gt 0)
  {
    $extraArgs["RecoveryLBBackendAddressPoolId"] = $LoadBalancerBackendAddressPools[0].Id
  }
  if ($FirstIPConfig.PrivateIpAllocationMethod -eq "Static")
  {
    $extraArgs["RecoveryStaticIPAddress"] = $FirstIPConfig.PrivateIpAddress
  }


  $ipConfig1 = New-AzRecoveryServicesAsrVMNicIPConfig -IpConfigName $FirstIPConfig.Name `
    -RecoverySubnetName $recoveryVnetSubnetName `
    -TfoSubnetName $testSubnetName `
    @extraArgs

  $NicGUID = ($RPI.NicDetailsList | Where-Object SourceNicArmId -eq $nic.Id).NicId


  $extraArgs = @{}
  if ($nic.EnableAcceleratedNetworking)
  {
    $extraArgs["EnableAcceleratedNetworkingOnRecovery"] = $true
    $extraArgs["EnableAcceleratedNetworkingOnTfo"] = $true
  }

  $nicConfig = New-AzRecoveryServicesAsrVMNicConfig -NicId $NicGUID -ReplicationProtectedItem $RPI `
    -RecoveryNetworkSecurityGroupId $RecoveryNetworkSecurityGroupId `
    -RecoveryVMNetworkId $RecoveryVnet.Id `
    -TfoVMNetworkId $TestVnet.Id `
    -TfoNetworkSecurityGroupId $TfoNetworkSecurityGroupId `
    -IPConfig @($ipConfig1) `
    @extraArgs

  $nicConfigs += $nicConfig
}

Set-AzRecoveryServicesAsrReplicationProtectedItem -InputObject $RPI -ASRVMNicConfiguration $nicConfigs
Write-Output "Networking changes submitted"
Write-Output "Check out Site Recovery jobs"
