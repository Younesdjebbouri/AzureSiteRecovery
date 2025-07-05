param(
    [parameter(Mandatory=$true)][ValidateSet("integration","preproduction","production")]$Environnement,
    [parameter(Mandatory=$False)][switch]$VersZoneSecondaire,
    [parameter(Mandatory=$False)][switch]$VersZoneNominale,
    [parameter(Mandatory=$True)][ValidateSet("app1")]$Application
)

$Parameters = @{
  "integration" = @{
    SubscriptionId = "00000000-0000-0000-0000-000000000001"
    env = "np"
    subenv = "int"
  }
  "preproduction" = @{
    SubscriptionId = "00000000-0000-0000-0000-000000000002"
    env = "pr"
    subenv = "ppd"
  }
  "production" = @{
    SubscriptionId = "00000000-0000-0000-0000-000000000003"
    env = "pr"
    subenv = "prd"
  }
}

if(!$VersZoneNominale -and !$VersZoneSecondaire)
{
  WriteLog "ERREUR - Vous devez spécifier au moins un des paramètres 'VersZoneNominale' ou 'VersZoneSecondaire'" ERROR
  exit
}

if($VersZoneNominale -and $VersZoneSecondaire)
{
  WriteLog "ERREUR - Vous ne pouvez pas spécifier les paramètre 'VersZoneNominale' et 'VersZoneSecondaire' en même temps, c'et l'un ou l'autre" ERROR
  exit
}

if($VersZoneSecondaire)
{
  $resourceGroupName = "rg-e2-$($Parameters[$Environnement]['env'])-app-$($Application)-$($Parameters[$Environnement]['subenv'])"
  switch($Application)
  {
    "app1"{
      $Zone = 1
    }
  }
  
}
else {
  $resourceGroupName = "rg-e2-$($Parameters[$Environnement]['env'])-asr-$($Application)-$($Parameters[$Environnement]['subenv'])"
  
  switch($Application)
  {
    "app1"{
      $Zone = 3
    }
  }
}

function WriteLog
{
  param (
    [string]$message,
    [string][ValidateSet('INFO','WARN','ERROR', 'SUCCESS')]$type
  )
  $date = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
  $typeStr = ""
  if ($type) { $typeStr = "-[" + $type + "]" }
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

set-azcontext -SubscriptionId $Parameters[$Environnement]['SubscriptionId'] | out-null

WriteLog "Tâche demandée : Lancement d'un failover"
WriteLog "Récupération des informations des Vms à modifier (paramétrage du tag disablestartandstop)" INFO
$VMsQuery = "resources
            | where type == 'microsoft.compute/virtualmachines' and resourceGroup == '$($ResourceGroupName)'
            | where zones[0] == '$($Zone)'
            | project name"

$Vms = Search-AzGraph -Query $VMsQuery

WriteLog "VM récupérées" SUCCESS
WriteLog "modification du tag disablestartandstop pour le passer à 'Start'" INFO
foreach($vm in $Vms)
{
  WriteLog " modification du tag de la VM $($vm.name)"
  $vm = Get-AzVM -Name $vm.name -ResourceGroupName $ResourceGroupName
  $vm.tags.disablestartandstop = "start"
  $vm | Update-AzVM
}
WriteLog "Paramétrage du tag réussi" SUCCESS
WriteLog "Fin de la tâche" SUCCESS
