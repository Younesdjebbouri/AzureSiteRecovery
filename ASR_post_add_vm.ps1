# Steps to finish registration of a VM in ASR

param(
  [Parameter(Mandatory = $true)][string]$vmName, # "vm-test-1"
  [Parameter(Mandatory = $true)][string]$resourceGroupSourceName, # "RG-TRO2"
  [Parameter(Mandatory = $true)][string]$resourceGroupDestName, # "RG-TRO2-asr"
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
  [Parameter(Mandatory = $true)][string]$testNetworkSecurityGroupName, # "nsg--test-failover"
  [Parameter(Mandatory = $true)][string]$storageReplication, # "testreplicationasr"
  [Parameter(Mandatory = $true)][string]$recoveryZone, # "2" or "1"
  [Parameter(ParameterSetName='crg',Mandatory = $false)][switch]$AddToCapacityReservationGroup,
  [Parameter(ParameterSetName='crg',Mandatory = $false)][string]$reservationGroupName
)

$ErrorActionPreference = "Stop"

$vault = Get-AzRecoveryServicesVault -Name $recoveryServiceVaultName -ResourceGroupName $recoveryServiceVaultResourceGroupName
Set-AzRecoveryServicesAsrVaultContext -Vault $vault -WarningAction SilentlyContinue | Out-Null
$Fabric = Get-AzRecoveryServicesAsrFabric -Name $asrFabricName
$ProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $Fabric -Name $asrProtectionContainer

while ($true)
{
  $now = Get-Date -Format "HH:mm:ss"
  Write-Output "[$now] Waiting for initial replication..."
  $RPI = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $ProtContainer -FriendlyName $vmName -ErrorAction Ignore
  if (($RPI.ProtectionState -eq "UnprotectedStatesBegin") -or ($null -eq $RPI.ProtectionState)) { Start-Sleep 10 }
  else { break }
}
Write-Output "Initial replication done"

while ($true)
{
  $now = Get-Date -Format "HH:mm:ss"
  Write-Output "[$now] Waiting for first recovery point..."
  $RPI = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $ProtContainer -FriendlyName $vmName
  if ($RPI.ProtectionState -ne "Protected") { Start-Sleep 10 }
  else { break }
}
Write-Output "Ready to update the virtual machine ASR config"


Write-Output "Disks configuration..."
.\ASR_set_disks_config.ps1 `
  -vmName $vmName `
  -resourceGroupSourceName $resourceGroupSourceName `
  -resourceGroupDestName $resourceGroupDestName `
  -asrFabricName $asrFabricName `
  -asrProtectionContainer $asrProtectionContainer `
  -recoveryServiceVaultName $recoveryServiceVaultName `
  -recoveryServiceVaultResourceGroupName $recoveryServiceVaultResourceGroupName `
  -storageReplication $storageReplication `
  -recoveryZone $recoveryZone

#if($AddToCapacityReservationGroup)
#{
#  if(($resourceGroupSourceName.Split('-'))[-1] -eq "prd" -or ($resourceGroupDestName.Split('-'))[-1] -eq "prd")
#  {
#    .\ASR_set_capacity_reservation.ps1 `
#      -vmName $vmName -reservationGroupName $reservationGroupName `
#      -resourceGroupDestName $resourceGroupDestName `
#      -asrFabricName $asrFabricName `
#      -asrProtectionContainer $asrProtectionContainer `
#      -recoveryServiceVaultName $recoveryServiceVaultName `
#      -recoveryServiceVaultResourceGroupName $recoveryServiceVaultResourceGroupName
#  }
#  else {
#    Write-Host "CRG - Impossible de pouvoir réserver la resources dans un capacity reservation group, assurez-vous que la VM est en production" -ForegroundColor Yellow
#  }
#}

Write-Output "Networking configuration..."
.\ASR_set_vm_advanced_networking.ps1 `
  -vmName $vmName `
  -resourceGroupSourceName $resourceGroupSourceName `
  -recoveryServiceVaultName $recoveryServiceVaultName `
  -recoveryServiceVaultResourceGroupName $recoveryServiceVaultResourceGroupName `
  -asrFabricName $asrFabricName `
  -asrProtectionContainer $asrProtectionContainer `
  -recoveryVnetName $recoveryVnetName `
  -recoveryVnetResourceGroupName $recoveryVnetResourceGroupName `
  -recoveryVnetSubnetName $recoveryVnetSubnetName `
  -testNetworkName $testNetworkName `
  -testNetworkResourceGroupName $testNetworkResourceGroupName `
  -testSubnetName $testSubnetName `
  -testNetworkSecurityGroupName $testNetworkSecurityGroupName
