<#
Synopsis: Register a VM for replication in Azure Site Recovery.
Description: Creates the replication protected item and associates networking and disks. Run after ASR_init.ps1.
#>

# Add a VM to Azure Site Recovery

param(
  [string]$fabricLocation = "francecentral",
  [Parameter(Mandatory = $true)][string]$vmName, 
  [Parameter(Mandatory = $true)][string]$resourceGroupSourceName, 
  [Parameter(Mandatory = $true)][string]$resourceGroupDestName,
  [Parameter(Mandatory = $true)][string]$recoveryVnetName, 
  [Parameter(Mandatory = $true)][string]$recoveryVnetResourceGroupName, 
  [Parameter(Mandatory = $true)][string]$recoveryVnetSubnetName, 
  [Parameter(Mandatory = $false)][string]$vmssDestName, 
  [Parameter(Mandatory = $false)][string]$recoveryZone,
  [Parameter(Mandatory = $true)][string]$storageReplication, 
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultName, 
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultResourceGroupName, 
  [Parameter(Mandatory = $true)][string]$testNetworkName, 
  [Parameter(Mandatory = $true)][string]$testNetworkResourceGroupName, 
  [Parameter(Mandatory = $true)][string]$testSubnetName, 
  [Parameter(Mandatory = $true)][string]$testNetworkSecurityGroupName, 
  [string]$project = "test",
  [Parameter(ParameterSetName='crg',Mandatory = $false)][switch]$AddToCapacityReservationGroup,
  [Parameter(ParameterSetName='crg',Mandatory = $false)][string]$reservationGroupName 
)

#if(!$AddToCapacityReservationGroup)
#{
#  if(($resourceGroupSourceName.Split('-'))[-1] -eq "prd" -or ($resourceGroupDestName.Split('-'))[-1] -eq "prd")
#  {
#    Write-Host "ERREUR - Vous avez spécifiés un/des groupe(s) de ressources en production sans avoir saisis de groupe de réservation de capacité. Veuillez relancer le script avec les bons paramètres" -ForegroundColor Red
#    exit
#  }
#}

$ErrorActionPreference = "Stop"

$asrFabricName = "$project-$fabricLocation-fabric"
$asrProtectionSourceContainer = "$project-1-fc-source-container"
$asrProtectionDestContainer = "$project-1-fc-destination-container"
$asrProtectionContainerMapping = "$project-1-mapping"
$asrProtectionContainerMappingReverse = "$project-1-mapping-reverse"

$vault = Get-AzRecoveryServicesVault -Name $recoveryServiceVaultName -ResourceGroupName $recoveryServiceVaultResourceGroupName
Set-AzRecoveryServicesAsrVaultContext -Vault $vault | Out-Null
$PrimaryFabric = Get-AzRecoveryServicesAsrFabric -Name $asrFabricName
$RecoveryFabric = $PrimaryFabric
$PrimaryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $PrimaryFabric -Name $asrProtectionSourceContainer
$RecoveryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $RecoveryFabric -Name $asrProtectionDestContainer
$ZoneProtectionMapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $PrimaryProtContainer -Name $asrProtectionContainerMapping
$ZoneProtectionMappingReverse = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $RecoveryProtContainer -Name $asrProtectionContainerMappingReverse # see ASR_reprotect.ps1

$CacheStorageAccount = Get-AzStorageAccount -ResourceGroupName $recoveryServiceVaultResourceGroupName -Name $storageReplication

#Get the resource group that the virtual machine must be created in when failed over.
$RecoveryRG = Get-AzResourceGroup -Name $resourceGroupDestName

#Get the VM to protect
$vm = Get-AzVM -ResourceGroupName $resourceGroupSourceName -Name $vmName
$sourceZone = $vm.Zones[0]

$extraArgs = @{}
$extraArgsPostAddVm = @{}
if($vmssDestName -and $recoveryZone)
{
  Write-Error "Specify either -vmssDestName or -recoveryZone but not both"
  Exit
}

if ($vmssDestName -ne "")
{
  #Get the destination scale set
  $vmss2 = Get-AzVmss -ResourceGroupName $resourceGroupDestName -Name $vmssDestName
  $recoveryZone = $vmss2.Zones[0]
  $extraArgs["RecoveryVirtualMachineScaleSetId"] = $vmss2.Id
}
elseif ($vmssDestName -eq "" -and $recoveryZone -eq "")
{
  Write-Error "Missing -recoveryZone"
  Exit
}


$disksconfig = .\ASR_get_disks_config.ps1 `
  -sourceZone $sourceZone `
  -recoveryZone $recoveryZone `
  -storageProfile $vm.StorageProfile `
  -localCacheStorageId $CacheStorageAccount.Id `
  -recoveryResourceGroupId $RecoveryRG.ResourceId


$recoveryVnet = Get-AzVirtualNetwork -Name $recoveryVnetName -ResourceGroupName $recoveryVnetResourceGroupName

#Start replication by creating replication protected item. Using a GUID for the name of the replication protected item to ensure uniqueness of name.
$RPI = New-AzRecoveryServicesAsrReplicationProtectedItem -AzureToAzure `
  -AzureVmId $VM.Id `
  -Name (New-Guid).Guid `
  -ProtectionContainerMapping $ZoneProtectionMapping `
  -AzureToAzureDiskReplicationConfiguration $disksconfig `
  -RecoveryResourceGroupId $RecoveryRG.ResourceId `
  -RecoveryAvailabilityZone $recoveryZone `
  -RecoveryAzureNetworkId $recoveryVnet.Id `
  -RecoveryAzureSubnetName $recoveryVnetSubnetName `
  @extraArgs

Write-Output "Item protection declared"
Write-Output "Check out Site Recovery jobs"

# if($AddToCapacityReservationGroup)
# {
#  if(($resourceGroupSourceName.Split('-'))[-1] -eq "prd" -or ($resourceGroupDestName.Split('-'))[-1] -eq "prd")
#  {
#    $extraArgsPostAddVm["AddToCapacityReservationGroup"] = $True
#    $extraArgsPostAddVm["reservationGroupName"] = $reservationGroupName
#  }
#  else {
#    Write-Host "CRG - Impossible de pouvoir réserver la resources dans un capacity reservation group, assurez-vous que la VM est en production" -ForegroundColor Yellow
#  }
# }

<#
.\ASR_add_vm.ps1 `
  -vmName $vmName `
  -fabricLocation $fabricLocation `
  -resourceGroupSourceName $resourceGroupSourceName `
  -resourceGroupDestName $resourceGroupDestName `
  -recoveryVnetName $recoveryVnetName `
  -recoveryVnetResourceGroupName $recoveryVnetResourceGroupName `
  -recoveryVnetSubnetName $recoveryVnetSubnetName `
  -vmssDestName $vmssDestName `
  -storageReplication $storageReplication `
  -recoveryServiceVaultName $recoveryServiceVaultName `
  -recoveryServiceVaultResourceGroupName $recoveryServiceVaultResourceGroupName `
  -testNetworkName $testNetworkName `
  -testNetworkResourceGroupName $testNetworkResourceGroupName `
  -testSubnetName $testSubnetName `
  -testNetworkSecurityGroupName $testNetworkSecurityGroupName `
  -reservationGroupName $reservationGroupName # si environnement de production
  -AddToCapacityReservationGroup # si environnement de production
  @extraArgsPostAddVm
#>