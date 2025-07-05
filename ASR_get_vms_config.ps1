# Overview of all VMs registered in a protection container

param(
  [Parameter(Mandatory = $true)][string]$asrFabricName, # "test-francecentral-fabric"
  [Parameter(Mandatory = $true)][string]$asrProtectionContainer, # "test-1-fc-source-container
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultName, # "rsv1"
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultResourceGroupName # "RG-TRO2-rsv"
)

$vault = Get-AzRecoveryServicesVault -Name $recoveryServiceVaultName -ResourceGroupName $recoveryServiceVaultResourceGroupName
Set-AzRecoveryServicesAsrVaultContext -Vault $vault | Out-Null
$PrimaryFabric = Get-AzRecoveryServicesAsrFabric -Name $asrFabricName
$ProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $PrimaryFabric -Name $asrProtectionContainer

$RPIs = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $ProtContainer

Write-Output "General:"
$RPIs | Select-Object RecoveryAzureVMName, TfoAzureVMName, RecoveryAzureVMSize, `
  @{Label='RecoveryVirtualMachineScaleSetName'; Expression={$_.ProviderSpecificDetails.RecoveryVirtualMachineScaleSetId.Split('/')[-1]}}, `
  @{Label='RecoveryAzureNetworkName'; Expression={$_.SelectedRecoveryAzureNetworkId.Split('/')[-1]}}, `
  @{Label='TfoAzureNetworkName'; Expression={$_.SelectedTfoAzureNetworkId.Split('/')[-1]}}, `
  @{Label='PrimaryAvailabilityZone'; Expression={$_.ProviderSpecificDetails.PrimaryAvailabilityZone}}, `
  @{Label='RecoveryAvailabilityZone'; Expression={$_.ProviderSpecificDetails.RecoveryAvailabilityZone}}, `
  ProtectionState, LastSuccessfulTestFailoverTime `
  | Sort-Object -Property RecoveryAzureVMName | Format-Table


Write-Output "Disks:"
$RPIs.ProviderSpecificDetails.A2ADiskDetails | Select-Object `
  DiskName, FailoverDiskName, TfoDiskName, DiskType, RecoveryTargetDiskAccountType `
  | Sort-Object -Property DiskName | Format-Table


Write-Output "Networking:"
$RPIs.NicDetailsList | Select-Object `
  @{Label='SourceNicArmId'; Expression={$_.SourceNicArmId.Split('/')[-1]}}, `
  # RecoveryNicName, TfoNicName, ` # not setted = same name
  @{Label='VMNetworkName'; Expression={$_.VMNetworkName.Split('/')[-1]}}, `
  @{Label='RecoveryVMNetworkName'; Expression={$_.RecoveryVMNetworkId.Split('/')[-1]}}, `
  @{Label='TfoVMNetworkName'; Expression={$_.TfoVMNetworkId.Split('/')[-1]}}, `
  @{Label='RecoveryNetworkSecurityGroupName'; Expression={$_.RecoveryNetworkSecurityGroupId.Split('/')[-1]}}, `
  @{Label='TfoNetworkSecurityGroupName'; Expression={$_.TfoNetworkSecurityGroupId.Split('/')[-1]}}, `

  # Hidden because columns takes too much space
  # EnableAcceleratedNetworkingOnRecovery, EnableAcceleratedNetworkingOnTfo

  @{Label='FirstIpConfigName'; Expression={$_.IpConfigs[0].Name}}, `
  @{Label='SubnetName'; Expression={$_.IpConfigs[0].SubnetName}}, `
  @{Label='RecoverySubnetName'; Expression={$_.IpConfigs[0].RecoverySubnetName}}, `
  @{Label='TfoSubnetName'; Expression={$_.IpConfigs[0].TfoSubnetName}}, `
  @{Label='RecoveryIPAddressType'; Expression={$_.IpConfigs[0].RecoveryIPAddressType}} | Sort-Object -Property SourceNicArmId | Format-Table
  # @{Label='StaticIPAddress'; Expression={$_.IpConfigs[0].StaticIPAddress}}, `
  # @{Label='RecoveryStaticIPAddress'; Expression={$_.IpConfigs[0].RecoveryStaticIPAddress}}, `
  # RecoveryLBBackendAddressPoolIds, TfoLBBackendAddressPoolIds `
  
