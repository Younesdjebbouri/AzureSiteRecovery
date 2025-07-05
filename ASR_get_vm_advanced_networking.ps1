<#
Synopsis: Display advanced networking properties for a replicated VM.
Description: Shows VM scale set information, NIC details and IP configuration from Azure Site Recovery.
#>

# Get advanced networking replication details for a VM

param(
  [Parameter(Mandatory = $true)][string]$vmName, # "vm-test-1"
  [Parameter(Mandatory = $true)][string]$asrFabricName, # "test-francecentral-fabric"
  [Parameter(Mandatory = $true)][string]$asrProtectionContainer, # "test-1-fc-source-container
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultName, # "rsv1"
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultResourceGroupName # "RG-TRO2-rsv"
)

$vault = Get-AzRecoveryServicesVault -Name $recoveryServiceVaultName -ResourceGroupName $recoveryServiceVaultResourceGroupName
Set-AzRecoveryServicesAsrVaultContext -Vault $vault | Out-Null
$Fabric = Get-AzRecoveryServicesAsrFabric -Name $asrFabricName
$ProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $Fabric -Name $asrProtectionContainer

$RPI = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $ProtContainer -FriendlyName $vmName

$RPI | Select-Object RecoveryAzureVMName,RecoveryAzureVMSize,SelectedRecoveryAzureNetworkId,TfoAzureVMName,SelectedTfoAzureNetworkId
$RPI.ProviderSpecificDetails | Select-Object RecoveryVirtualMachineScaleSetId,A2ADiskDetails
$RPI.NicDetailsList | Select-Object EnableAcceleratedNetworkingOnRecovery,RecoveryVMNetworkId,RecoveryNetworkSecurityGroupId,EnableAcceleratedNetworkingOnTfo,TfoVMNetworkId,TfoNetworkSecurityGroupId
$RPI.NicDetailsList.IpConfigs
