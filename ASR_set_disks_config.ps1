<#
Synopsis: Update disk replication settings for a protected VM.
Description: Adds new disks if needed and adjusts cache storage before applying the configuration.
#>

# Define replicated disks name and cache storage

param(
  [Parameter(Mandatory = $true)][string]$vmName, # "vm-test-1",
  [Parameter(Mandatory = $true)][string]$resourceGroupSourceName, # "RG-TRO2",
  [Parameter(Mandatory = $true)][string]$resourceGroupDestName, # "RG-TRO2-asr",
  [Parameter(Mandatory = $true)][string]$asrFabricName, # "test-francecentral-fabric",
  [Parameter(Mandatory = $true)][string]$asrProtectionContainer, # "test-1-fc-source-container",
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultName, # "rsv1",
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultResourceGroupName, # "RG-TRO2-rsv",
  [Parameter(Mandatory = $true)][string]$storageReplication, # "testreplicationasr"
  [Parameter(Mandatory = $true)][string]$recoveryZone # "2" or "1"
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
$sourceZone = $vm.Zones[0]

$RecoveryRG = Get-AzResourceGroup -Name $resourceGroupDestName

$CacheStorageAccount = Get-AzStorageAccount -ResourceGroupName $recoveryServiceVaultResourceGroupName -Name $storageReplication

$disksconfig = .\ASR_get_disks_config.ps1 `
  -sourceZone $sourceZone `
  -recoveryZone $recoveryZone `
  -storageProfile $vm.StorageProfile `
  -localCacheStorageId $CacheStorageAccount.Id `
  -recoveryResourceGroupId $RecoveryRG.ResourceId

$toFilter = @()
foreach ($diskconfig in $disksconfig)
{
  $diskName = $diskconfig.DiskId.Split("/")[-1]
  $RPIDisk = $RPI.ProviderSpecificDetails.A2ADiskDetails | Where-Object DiskName -eq $diskName
  if ($null -eq $RPIDisk)
  {
    Write-Output "New disk to declare: $diskName"
    Add-AzRecoveryServicesAsrReplicationProtectedItemDisk `
      -InputObject $RPI `
      -AzureToAzureDiskReplicationConfiguration $diskconfig
    $toFilter += $diskconfig.DiskId
  }
}
# Prevent updating error in next command (need time to declare new disk)
$disksconfig = $disksconfig | Where-Object { $_.DiskId -notin $toFilter }

Set-AzRecoveryServicesAsrReplicationProtectedItem `
  -InputObject $RPI `
  -AzureToAzureUpdateReplicationConfiguration $disksconfig
Write-Output "Disks changes submitted"
Write-Output "Check out Site Recovery jobs"
