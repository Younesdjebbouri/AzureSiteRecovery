<#
Synopsis: Synchronize ASG configuration between source and destination VMs during online failover.
Description: Reads ASG assignments from the primary NIC and applies them to the replicated NIC.
#>

param(
  [Parameter(Mandatory = $true)][string]$sid, #ex: 8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf, subscription id
  [Parameter(Mandatory = $true)][string]$RgPrimaire, #ex: RG-TEst-ASR
  [Parameter(Mandatory = $true)][string]$RgSecondaire,
  [Parameter(Mandatory = $false)][string[]]$VirtualMachines
)

$ErrorActionPreference = "Stop"
Set-AzContext -SubscriptionId $sid | Out-Null

$VMs = Get-AzVM -ResourceGroupName $RgPrimaire
if ($VirtualMachines.Count -gt 0)
{
  $VMs = $VMs | Where-Object {$VirtualMachines.Contains($_.Name)}
}

foreach ($vm in $VMs)
{
  $ReplicatedVM = Get-AzVM -Name $vm.Name -ResourceGroupName $RgSecondaire -ErrorAction Ignore
  if (!$ReplicatedVM)
  {
    Write-Output ""
    Write-Warning "Pas de VM répliquée dans $RgSecondaire portant le nom de $($vm.Name)"
    Write-Output ""
    continue
  }

  Write-Output "Récupération infos de la NIC sur la VM $($vm.Name)"
  $SplittedNicId = ($vm.NetworkProfile.NetworkInterfaces.Id).Split('/')
  $NicName = $SplittedNicId[-1]
  $Nic = Get-AzNetworkInterface -Name $NicName -ResourceGroupName $RgPrimaire

  ###### Récupération des ASG à transférer ######
  Write-Output "Récupération des ASG à transférer"
  $AllASGs = $Nic.IpConfigurations[0].ApplicationSecurityGroups

  ###### Récupération des infos de la nouvelle carte réseau ######
  Write-Output "Récupération des infos de la nouvelle carte réseau"
  $NewSplittedNicId = ($ReplicatedVM.NetworkProfile.NetworkInterfaces.Id).Split('/')
  $NewNicName = $NewSplittedNicId[-1]
  $NewNic = Get-AzNetworkInterface -Name $NewNicName -ResourceGroupName $RgSecondaire

  ###### Mise à jour des paramètres ASG sur la nouvelle carte réseau ######
  Write-host "Mise à jour de la nouvelle carte réseau"
  $NicUpdate = Set-AzNetworkInterfaceIpConfig -Name $NewNic.IpConfigurations[0].Name -NetworkInterface $NewNic -ApplicationSecurityGroup $AllASGs
  $NicUpdate | Set-AzNetworkInterface | Out-Null
  Write-Host "Carte réseau $($NewNic.Name) sauvegardée"
}
