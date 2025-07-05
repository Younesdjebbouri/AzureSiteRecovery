<#
Synopsis: Specify the destination VM scale set for a replicated VM.
Description: Updates the replication protected item so failover creates the VM inside the provided VMSS.
#>

# Define destination scale set

param(
  [Parameter(Mandatory = $true)][string]$vmName, # "vm-test-1",
  [Parameter(Mandatory = $true)][string]$vmssDestName, # "vmss1-test-az2",
  [Parameter(Mandatory = $true)][string]$resourceGroupDestName, # "RG-TRO2-asr",
  [Parameter(Mandatory = $true)][string]$asrFabricName, # "test-francecentral-fabric",
  [Parameter(Mandatory = $true)][string]$asrProtectionContainer, # "test-1-fc-source-container",
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultName, # "rsv1",
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultResourceGroupName # "RG-TRO2-rsv"
)

$ErrorActionPreference = "Stop"

$vault = Get-AzRecoveryServicesVault -Name $recoveryServiceVaultName -ResourceGroupName $recoveryServiceVaultResourceGroupName
Set-AzRecoveryServicesAsrVaultContext -Vault $vault | Out-Null
$Fabric = Get-AzRecoveryServicesAsrFabric -Name $asrFabricName
$ProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $Fabric -Name $asrProtectionContainer

$RPI = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $ProtContainer -FriendlyName $vmName
if ($RPI.ProtectionState -ne "Protected")
{
  Write-Warning "VM not protected yet, stopping"
  Exit
}

$vmss = Get-AzVmss -ResourceGroupName $resourceGroupDestName -Name $vmssDestName

Set-AzRecoveryServicesAsrReplicationProtectedItem `
  -InputObject $RPI `
  -RecoveryVirtualMachineScaleSetId $vmss.Id
Write-Output "Capacity reservation job submitted"
Write-Output "Check out Site Recovery jobs"
