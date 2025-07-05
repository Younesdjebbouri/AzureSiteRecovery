<#
Synopsis: Start replication back to the primary zone after a failover.
Description: Builds new replication settings and waits until the VM is protected again.
#>

# Reprotect after failover from recovery to main

param(
  [string]$fabricLocation = "francecentral",
  [Parameter(Mandatory = $true)][string]$vmName, # "test-vm-1"
  [Parameter(Mandatory = $false)][string]$vmssDestName, # "vmss1"
  [Parameter(Mandatory = $false)][string]$recoveryZone, # "2" ; only if $vmssDestName is ""
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultName, # "rsv1"
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultResourceGroupName, # "RG-TRO2"
  [Parameter(Mandatory = $true)][string]$resourceGroupDestName, # "RG-TRO2"
  [Parameter(Mandatory = $true)][string]$resourceGroupSourceName, # "RG-TRO2-asr"
  [Parameter(Mandatory = $true)][string]$storageReplication, # "testreplicationasr",
  [Parameter(Mandatory = $true)][string]$recoveryVnetName, # "RG-TRO2-vnet"
  [Parameter(Mandatory = $true)][string]$recoveryVnetResourceGroupName, # "RG-TRO2"
  [Parameter(Mandatory = $true)][string]$recoveryVnetSubnetName, # "default"
  [Parameter(Mandatory = $true)][string]$testNetworkName, # "vn-test-1"
  [Parameter(Mandatory = $true)][string]$testNetworkResourceGroupName, # "RG-TRO2"
  [Parameter(Mandatory = $true)][string]$testSubnetName, # "sub-test-1"
  [Parameter(Mandatory = $true)][string]$testNetworkSecurityGroupName, # "nsg-test-failover"
  [string]$project = "test",
  [string]$capacityReservationGroupDest
)

$ErrorActionPreference = "Stop"


$asrFabricName = "$project-$fabricLocation-fabric"
$asrProtectionSourceContainer = "$project-1-fc-source-container"
$asrProtectionDestContainer = "$project-1-fc-destination-container"
$asrProtectionContainerMapping = "$project-1-mapping"
$asrProtectionContainerMappingReverse = "$project-1-mapping-reverse"

if($vmssDestName -and $recoveryZone)
{
  Write-Error "Specify either -vmssDestName or -recoveryZone but not both"
  Exit
}
$vmssDest = $null
if ($vmssDestName -ne "")
{
  # Get the destination scale set
  $vmssDest = Get-AzVmss -ResourceGroupName $resourceGroupDestName -Name $vmssDestName
  $recoveryZone = $vmssDest.Zones[0]
}
elseif ($vmssDestName -eq "" -and $recoveryZone -eq "")
{
  Write-Error "Missing -recoveryZone"
  Exit
}

$protectionDirection = "SourceToDestination"
if ($resourceGroupSourceName.Contains("-asr")) { $protectionDirection = "DestinationToSource" }

$vault = Get-AzRecoveryServicesVault -Name $recoveryServiceVaultName -ResourceGroupName $recoveryServiceVaultResourceGroupName
Set-AzRecoveryServicesAsrVaultContext -Vault $vault | Out-Null
$PrimaryFabric = Get-AzRecoveryServicesAsrFabric -Name $asrFabricName
$RecoveryFabric = $PrimaryFabric
if ($protectionDirection -eq "DestinationToSource")
{
  $PrimaryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $PrimaryFabric -Name $asrProtectionSourceContainer
  $RecoveryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $RecoveryFabric -Name $asrProtectionDestContainer
  $ZoneProtectionMapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $RecoveryProtContainer -Name $asrProtectionContainerMappingReverse
}
else # Second reprotect (like the initial protection in ASR_add_vm.ps1)
{
  $PrimaryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $PrimaryFabric -Name $asrProtectionDestContainer
  $RecoveryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $RecoveryFabric -Name $asrProtectionSourceContainer
  $ZoneProtectionMapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $PrimaryProtContainer -Name $asrProtectionContainerMapping
}

$RPI = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $PrimaryProtContainer -FriendlyName $vmName

$CacheStorageAccount = Get-AzStorageAccount -ResourceGroupName $recoveryServiceVaultResourceGroupName -Name $storageReplication
$RecoveryRG = Get-AzResourceGroup -Name $resourceGroupDestName

$vm = Get-AzVM -ResourceGroupName $resourceGroupSourceName -Name $vmName
$sourceZone = $vm.Zones[0]


$disksconfig = .\ASR_get_disks_config.ps1 `
  -sourceZone $sourceZone `
  -recoveryZone $recoveryZone `
  -storageProfile $vm.StorageProfile `
  -localCacheStorageId $CacheStorageAccount.Id `
  -recoveryResourceGroupId $RecoveryRG.ResourceId

$extraArgs = @{}
if ($capacityReservationGroupDest)
{
  $reservationCapacityGroupDest = Get-AzCapacityReservationGroup -ResourceGroupName $resourceGroupDestName -Name $capacityReservationGroupDest
  $extraArgs["RecoveryCapacityReservationGroupId"] = $reservationCapacityGroupDest.Id
}
if ($protectionDirection -eq "SourceToDestination")
{
  if ($null -ne $vmssDest)
  {
    # Avoids Error ID 150405
    # The source virtual machine is in a virtual machine scale set. Site Recovery requires the target virtual machine scale set to be provided for such VMs.
    $extraArgs["RecoveryVirtualMachineScaleSetId"] = $vmssDest.Id
  }

  # Avoids Error ID 28172
  # The resource group: '' of the target virtual machine and the resource group of the target virtual machine scale set '/subscriptions/*********/resourceGroups/RG-TRO2-asr/providers/Microsoft.Compute/virtualMachineScaleSets/vmss1-asr' should be the same.
  $extraArgs["RecoveryResourceGroupId"] = $RecoveryRG.ResourceId

  # Fails with Errors ID 28168
  # Target virtual machine scale set: '/subscriptions/*********/resourceGroups/RG-TRO2-asr/providers/Microsoft.Compute/virtualMachineScaleSets/vmss1-asr' is zonal and target availability zone is not specified.

  # => only way right now is to disable replication and re-register the vm with ASR_add_vm.ps1
}

Update-AzRecoveryServicesAsrProtectionDirection -AzureToAzure `
  -ProtectionContainerMapping $ZoneProtectionMapping `
  -AzureToAzureDiskReplicationConfiguration $disksconfig `
  -ReplicationProtectedItem $RPI `
  @extraArgs


while ($true)
{
  $now = Get-Date -Format "HH:mm:ss"
  Write-Output "[$now] Waiting for reprotection..."
  $RPI = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $RecoveryProtContainer -FriendlyName $vmName -ErrorAction Ignore
  if ($null -eq $RPI -or $RPI.ProtectionState -ne "Protected") { Start-Sleep 10 }
  else { break }
}

.\ASR_set_vm_advanced_networking.ps1 `
  -vmName $vmName `
  -resourceGroupSourceName $resourceGroupSourceName `
  -recoveryServiceVaultName $recoveryServiceVaultName `
  -recoveryServiceVaultResourceGroupName $recoveryServiceVaultResourceGroupName `
  -asrFabricName $asrFabricName `
  -asrProtectionContainer $asrProtectionDestContainer `
  -recoveryVnetName $recoveryVnetName `
  -recoveryVnetResourceGroupName $recoveryVnetResourceGroupName `
  -recoveryVnetSubnetName $recoveryVnetSubnetName `
  -testNetworkName $testNetworkName `
  -testNetworkResourceGroupName $testNetworkResourceGroupName `
  -testSubnetName $testSubnetName `
  -testNetworkSecurityGroupName $testNetworkSecurityGroupName
