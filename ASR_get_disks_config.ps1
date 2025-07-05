<#
Synopsis: Build disk replication configuration objects.
Description: Helper script used by other commands to prepare OS and data disk settings for A2A replication.
#>

# Obtain informations to replicate disks

param(
  [Parameter(Mandatory = $true)][string]$sourceZone, # "1"
  [Parameter(Mandatory = $true)][string]$recoveryZone, # "2"
  [Parameter(Mandatory = $true)]$storageProfile, # of the vm
  [Parameter(Mandatory = $true)]$localCacheStorageId,
  [Parameter(Mandatory = $true)]$recoveryResourceGroupId
)

$ErrorActionPreference = "Stop"

function ReplaceDiskName($diskName)
{
  $suffix = "-az$recoveryZone"
  $res = $diskName.replace("-az$sourceZone", $suffix)
  if ($res.EndsWith($suffix) -eq $false)
  {
    $res += $suffix
  }
  return $res
}

# Os Disk
$OSdisk = $storageProfile.OsDisk
$OSdiskId = $OSdisk.ManagedDisk.Id
$RecoveryTargetOSDiskAccountType = $OSdisk.ManagedDisk.StorageAccountType
$RecoveryReplicaOSDiskAccountType = $OSdisk.ManagedDisk.StorageAccountType
if ($null -eq $RecoveryTargetOSDiskAccountType) # vm likely shut down
{
  $d = Get-AzDisk -Name $OSdisk.Name -ResourceGroupName $OSdiskId.Split("/")[4]
  $RecoveryTargetOSDiskAccountType = $d.Sku.Name
  $RecoveryReplicaOSDiskAccountType = $d.Sku.Name
}

$FailoverDiskName = ReplaceDiskName $OSdisk.Name
$TfoDiskName = "$FailoverDiskName-ASRtest"

$OSDiskReplicationConfig = New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -ManagedDisk `
  -LogStorageAccountId $localCacheStorageId `
  -DiskId $OSdiskId `
  -RecoveryResourceGroupId $recoveryResourceGroupId `
  -RecoveryReplicaDiskAccountType  $RecoveryReplicaOSDiskAccountType `
  -RecoveryTargetDiskAccountType $RecoveryTargetOSDiskAccountType `
  -FailoverDiskName $FailoverDiskName `
  -TfoDiskName $TfoDiskName

#Create a list of disk replication configuration objects for the disks of the virtual machine that are to be replicated.
$disksconfig = @($OSDiskReplicationConfig)

# Data Disks
foreach ($dataDisk in $storageProfile.DataDisks)
{
  $DatadiskId = $dataDisk.ManagedDisk.Id
  $RecoveryTargetDiskAccountType = $dataDisk.ManagedDisk.StorageAccountType
  $RecoveryReplicaDiskAccountType = $dataDisk.ManagedDisk.StorageAccountType
  if ($null -eq $RecoveryTargetDiskAccountType) # vm likely shut down
  {
    $d = Get-AzDisk -Name $dataDisk.Name -ResourceGroupName $DatadiskId.Split("/")[4]
    $RecoveryTargetDiskAccountType = $d.Sku.Name
    $RecoveryReplicaDiskAccountType = $d.Sku.Name
  }

  $FailoverDiskName = ReplaceDiskName $dataDisk.Name
  $TfoDiskName = "$FailoverDiskName-ASRtest"

  $DataDiskReplicationConfig = New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -ManagedDisk `
    -LogStorageAccountId $localCacheStorageId `
    -DiskId $DatadiskId `
    -RecoveryResourceGroupId $recoveryResourceGroupId `
    -RecoveryReplicaDiskAccountType $RecoveryReplicaDiskAccountType `
    -RecoveryTargetDiskAccountType $RecoveryTargetDiskAccountType `
    -FailoverDiskName $FailoverDiskName `
    -TfoDiskName $TfoDiskName

  $disksconfig += $DataDiskReplicationConfig
}

return $disksconfig
