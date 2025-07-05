# Initial configuration of Azure Site Recovery

param(
  [string]$fabricLocation = "francecentral",
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultName,
  [Parameter(Mandatory = $true)][string]$recoveryServiceVaultResourceGroupName,
  [string]$project = "test"
)

$ErrorActionPreference = "Stop"

$asrFabricName = "$project-$fabricLocation-fabric"
$asrProtectionSourceContainer = "$project-1-fc-source-container"
$asrProtectionDestContainer = "$project-1-fc-destination-container"
$asrReplicationPolicy = "$project-1-policy"
$asrProtectionContainerMapping = "$project-1-mapping"
$asrProtectionContainerMappingReverse = "$project-1-mapping-reverse"

# Number of days (hours) up to which the recovery points will be retained.
# Specify a valid number from 0 to 15 (0 to 360). If you specify 0, then there will be no additional recovery points and you can failover only to the latest point.
$RecoveryPointRetentionInHours = 24
# App-consistent snapshot frequency (in hours). Specify a valid number from 0 to 12
$ApplicationConsistentSnapshotFrequencyInHours = 2


#Get the vault
$vault = Get-AzRecoveryServicesVault -Name $recoveryServiceVaultName -ResourceGroupName $recoveryServiceVaultResourceGroupName

#Setting the vault context.
Set-AzRecoveryServicesAsrVaultContext -Vault $vault | Out-Null

# --------------------------------------------------

Write-Output "Create ASR fabric"
$TempASRJob = New-AzRecoveryServicesAsrFabric -Azure -Location $fabricLocation -Name $asrFabricName
# Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted"))
{
  #If the job hasn't completed, sleep for 10 seconds before checking the job status again
  Start-Sleep 10
  $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
  Write-Output "..."
}
#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State

$PrimaryFabric = Get-AzRecoveryServicesAsrFabric -Name $asrFabricName
$RecoveryFabric = $PrimaryFabric

# --------------------------------------------------

Write-Output "Create a Protection container in the primary Azure region (within the Primary fabric)"
$TempASRJob = New-AzRecoveryServicesAsrProtectionContainer -InputObject $PrimaryFabric -Name $asrProtectionSourceContainer
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted"))
{
  Start-Sleep 10
  $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
  Write-Output "..."
}
Write-Output $TempASRJob.State

$PrimaryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $PrimaryFabric -Name $asrProtectionSourceContainer

# --------------------------------------------------

Write-Output "Create a Protection container in the recovery Azure region (within the Recovery fabric)"
$TempASRJob = New-AzRecoveryServicesAsrProtectionContainer -InputObject $RecoveryFabric -Name $asrProtectionDestContainer
#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted"))
{
  Start-Sleep 10
  $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
  Write-Output "..."
}
#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State

$RecoveryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $RecoveryFabric -Name $asrProtectionDestContainer

# --------------------------------------------------

Write-Output "Create replication policy"
$TempASRJob = New-AzRecoveryServicesAsrPolicy -AzureToAzure -Name $asrReplicationPolicy -RecoveryPointRetentionInHours $RecoveryPointRetentionInHours -ApplicationConsistentSnapshotFrequencyInHours $ApplicationConsistentSnapshotFrequencyInHours
#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted"))
{
  Start-Sleep 10
  $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
  Write-Output "..."
}
#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State

$ReplicationPolicy = Get-AzRecoveryServicesAsrPolicy -Name $asrReplicationPolicy

# --------------------------------------------------

Write-Output "Create Protection container mapping between the Primary and Recovery Protection Containers with the Replication policy"
$TempASRJob = New-AzRecoveryServicesAsrProtectionContainerMapping -Name $asrProtectionContainerMapping -Policy $ReplicationPolicy -PrimaryProtectionContainer $PrimaryProtContainer -RecoveryProtectionContainer $RecoveryProtContainer
#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted"))
{
  Start-Sleep 10
  $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
  Write-Output "..."
}
#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State

$ZoneProtectionMapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $PrimaryProtContainer -Name $asrProtectionContainerMapping

# --------------------------------------------------

Write-Output "Create Protection container mapping (for fail back) between the Recovery and Primary Protection Containers with the Replication policy"
$TempASRJob = New-AzRecoveryServicesAsrProtectionContainerMapping -Name $asrProtectionContainerMappingReverse -Policy $ReplicationPolicy -PrimaryProtectionContainer $RecoveryProtContainer -RecoveryProtectionContainer $PrimaryProtContainer
#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted"))
{
  Start-Sleep 10
  $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
  Write-Output "..."
}
#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State

$ReverseZoneProtectionMapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $RecoveryProtContainer -Name $asrProtectionContainerMappingReverse

Write-Output "Finished, all set!"
