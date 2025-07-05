param(
  [Parameter(Mandatory = $true)][string]$sid, #ex: 8197d8ee-bdff-4gba-bvds-bd38sdfvxvf3, subscription id
  [Parameter(Mandatory = $False)][string]$RgPrimaire, # resource group where VM are going to be updated
  [Parameter(Mandatory = $true)][string]$RgDestination, # resource group where VM are replicated
  [Parameter(Mandatory = $False)][string]$CustomFilePath,
  [Parameter(Mandatory = $False)][switch]$CentralServerOnly
)

function WriteLog
{
  param (
    [string]$message,
    [string][ValidateSet('INFO','WARN','ERROR', 'SUCCESS')]$type
  )
  $date = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
  $typeStr = ""
  if ($type) { $typeStr = "[" + $type + "]-" }
  $log = $typeStr + $date + "-" + $message
  switch ($type)
  {
    "SUCCESS" {$color = "Green"}
    "INFO" { $color = "Blue" }
    "WARN" { $color = "Yellow" }
    "ERROR" { $color = "Red" }
    default { $color = "White" }
  }
  Write-Host $log -ForegroundColor $color
}


$ErrorActionPreference = "Stop"
Set-AzContext -SubscriptionId $sid | Out-Null
$extraArgs = @{}
$VMQuery = "resources
              | where type == 'microsoft.compute/virtualmachines' and resourceGroup == '$($RgPrimaire)'
              | where tags['test-function'] == 'central'
              | project name"
$Centralname = (Search-AzGraph -Query $VMQuery).name
$FileFilter = "*json"
if($CentralServerOnly)
{
  $FileFilter = "$($Centralname).json"
}
else {
  $extraArgs["Exclude"] = "$($Centralname).json"
}

if($CustomFilePath)
{
   $extraArgs["Path"] = "$CustomFilePath"
}
else {
  if(!$RgPrimaire)
  {
    $RgPrimaire = Read-Host "RgPrimaire"
  }

  $extraArgs["Path"] = "config/$RgPrimaire"
}
$ConfigFiles = Get-ChildItem -Filter $FileFilter @extraArgs

foreach ($file in $ConfigFiles)
{
  $FileContent = Get-Content -Path $file.FullName | ConvertFrom-Json
  foreach ($Record in $FileContent)
  {
    $ReplicatedVM = Get-AzVM -Name $Record.VMName -ResourceGroupName $RgDestination -ErrorAction Ignore
    if (!$ReplicatedVM)
    {
      Write-Output ""
      WriteLog "Pas de VM répliquée dans $RgDestination portant le nom de $($Record.VMName)" -type WARN
      Write-Output ""
      continue
    }

    WriteLog "Récupération des infos de la nouvelle carte réseau $($Record.NicName) de la VM $($Record.VMName) dans $RgDestination" -type INFO
    $ReplicatedNic = $ReplicatedVM.NetworkProfile.NetworkInterfaces | Where-Object -FilterScript {
      ($_.Id.Split("/")[-1] -eq $Record.NicName)
    }
    if ($ReplicatedNic.Count -eq 0)
    {
      WriteLog "Carte réseau $($Record.NicName) non trouvée sur la VM $($Record.VMName) dans $RgDestination" -type ERROR
      continue
    }

    $NewSplittedNicId = ($ReplicatedNic.Id).Split('/')
    $NewNicName = $NewSplittedNicId[-1]
    $NicResourceGroup = $NewSplittedNicId[4]
    $NewNic = Get-AzNetworkInterface -Name $NewNicName -ResourceGroupName $NicResourceGroup
    $NewIpConfig = $NewNic.IpConfigurations[0]
    $SubnetName = ($NewIpConfig.Subnet.Id).Split('/')[-1]

    WriteLog "récupération des infos de load balancing sur la nouvelle carte réseau..." -type INFO

    $BackendPoolIdsToAdd = @()
    $NewIpConfig.LoadBalancerBackendAddressPools | foreach-object {
      # Keep existing backendpool, if any
      $BackendPoolIdsToAdd += $_.Id
    }

    foreach ($bpid in $Record.LBs)
    {
      $BackendPoolName = ($bpid).Split('/')[-1]

      $HasBackendPoolAssociation = ($BackendPoolIdsToAdd | Where-Object -FilterScript {$_ -eq $bpid}).Count -eq 1
      if ($HasBackendPoolAssociation)
      {
        WriteLog "La carte réseau $NewNicName du $RgDestination est déjà associée au backend pool $BackendPoolName" -type INFO
      }
      else
      {
        $BackendPoolIdsToAdd += $bpid
      }
    }

    if (($Record.Subnet -eq $SubnetName))
    {
      WriteLog "Mise a jour de la carte réseau $NewNicName du $RgDestination avec les paramètres ASG de $($file.Name)" -type INFO
      $NicUpdate = Set-AzNetworkInterfaceIpConfig -Name $NewIpConfig.Name `
        -NetworkInterface $NewNic `
        -ApplicationSecurityGroupId $Record.ASGs `
        -LoadBalancerBackendAddressPoolId $BackendPoolIdsToAdd

      $NicUpdate | Set-AzNetworkInterface | Out-Null
      WriteLog "Carte réseau $($NewNic.Name) sauvegardée" -ForegroundColor Green -type INFO
    }
    else
    {
      WriteLog "Missmatch subnet de la carte réseau $NewNicName du $RgDestination avec les paramètres ASG de $($file.Name)" -type WARN
    }
  }
}
WriteLog "DONE - Reconfiguration terminée à partir des informations récupérées dans les fichiers 
JSON préalablement alimentés. Assurez-vous tout de même que vos machines ont bien 
récupéré toutes les informations nécessaires à leur bon fonctionnement !" -type WARN
Write-Output ""
