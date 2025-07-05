<#
.SYNOPSIS
    Script générique pour la bascule Azure Site Recovery (ASR).
.DESCRIPTION
    Ce script permet de gérer la bascule entre zones nominale et secondaire pour une application donnée.
    Exemple : ici, l'application "app1" est utilisée, mais vous pouvez adapter ce paramètre selon vos besoins.
#>

param(
    [parameter(Mandatory=$True)][string][ValidateSet("integration","preproduction","production")]$Environnement,
    [parameter(Mandatory=$False)][switch]$VersZoneSecondaire,
    [parameter(Mandatory=$False)][switch]$VersZoneNominale,
    # Remplacez "app1" par le nom de votre application si besoin
    [parameter(Mandatory=$True)][string]$Application = "app1"
)

$ErrorActionPreference = "Stop"

# Paramètres génériques pour chaque environnement
$Parameters = @{
    "integration" = @{
        SubscriptionId = "<integration-subscription-id>"
        storageAccountName = "storageaccount$($Application)int"
        ContainerName = "export-vms-infos"
        storageaccountresourcegroupname = "rg-integration-app-$($Application)-int"
        env = "integration"
        subenv = "int"
    }
    "preproduction" = @{
        SubscriptionId = "<preproduction-subscription-id>"
        storageAccountName = "storageaccount$($Application)pre"
        ContainerName = "export-vms-infos"
        storageaccountresourcegroupname = "rg-preproduction-app-$($Application)-pre"
        env = "preproduction"
        subenv = "pre"
    }
    "production" = @{
        SubscriptionId = "<production-subscription-id>"
        storageAccountName = "storageaccount$($Application)prod"
        ContainerName = "export-vms-infos"
        storageaccountresourcegroupname = "rg-production-app-$($Application)-prod"
        env = "production"
        subenv = "prod"
    }
}

if(!$VersZoneNominale -and !$VersZoneSecondaire)
{
  WriteLog "ERREUR - Vous devez spécifier au moins un des paramètres 'VersZoneNominale' ou 'VersZoneSecondaire'" ERROR
  exit
}

if($VersZoneNominale -and $VersZoneSecondaire)
{
  WriteLog "ERREUR - Vous ne pouvez pas spécifier les paramètres 'VersZoneNominale' et 'VersZoneSecondaire' en même temps, c'est l'un ou l'autre" ERROR
  exit
}

# Construction dynamique des noms de groupes de ressources selon la zone cible
if($VersZoneNominale)
{
  $resourceGroupName = "rg-e2-$($Parameters[$Environnement]['env'])-asr-$($Application)-$($Parameters[$Environnement]['subenv'])"
  $ResourceGroupDestName = "rg-e2-$($Parameters[$Environnement]['env'])-app-$($Application)-$($Parameters[$Environnement]['subenv'])"
}

if($VersZoneSecondaire){
  $resourceGroupName = "rg-e2-$($Parameters[$Environnement]['env'])-app-$($Application)-$($Parameters[$Environnement]['subenv'])"
  $ResourceGroupDestName = "rg-e2-$($Parameters[$Environnement]['env'])-asr-$($Application)-$($Parameters[$Environnement]['subenv'])"
}

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

Set-AzContext -SubscriptionId $Parameters[$Environnement]['SubscriptionId'] | out-null

try {
    WriteLog "Autorisation de l'adresse IP de la session Cloud Shell dans le firewall du compte de stockage cible" -type INFO
    $IPtoAllow = (curl "ifconfig.me")
    Add-AzStorageAccountNetworkRule -ResourceGroupName $Parameters[$Environnement]['storageaccountresourcegroupname'] -AccountName $Parameters[$Environnement]['storageAccountName'] -IPAddressOrRange $IPtoAllow | out-null

    $key = ConvertTo-SecureString -String "$(((Get-AzStorageAccountKey -ResourceGroupName $Parameters[$Environnement]['storageaccountresourcegroupname'] -Name $Parameters[$Environnement]['storageAccountName'] | where-object {$_.KeyName -eq "key1"}).value))" -AsPlainText
    $ctx = New-AzStorageContext -StorageAccountName $Parameters[$Environnement]['storageAccountName'] -StorageAccountKey (ConvertFrom-SecureString -SecureString $key -AsPlainText)

    WriteLog "Création du SAS Token pour accéder au compte de stockage cible" -type INFO
    $SASToken = ConvertTo-SecureString -String "$(New-AzStorageAccountSASToken -Service Blob -ResourceType Service,Container,Object -Permission "rl" -ExpiryTime (get-date).AddDays(1) -Context $ctx -IPAddressOrRange $IPtoAllow)" -AsPlainText
    $SASUrl = "$($ctx.BlobEndPoint)$($Parameters[$Environnement]['ContainerName'])/?$(ConvertFrom-SecureString -SecureString $SASToken -AsPlainText)" 
    WriteLog "Attente de 30 secondes pour la prise en compte de la règle et du SAS token..." -type INFO
    start-sleep -seconds 30
    WriteLog "Copie des fichiers..." -type INFO
    azcopy copy "$($SASUrl)" . --recursive
    WriteLog "SUCCESS !"

    WriteLog "Suppression de l'adresse IP de la session Cloud Shell dans le firewall du compte de stockage cible" -type INFO
    remove-azstorageAccountNetworkRule -IPAddressOrRange  $IPtoAllow -Name $Parameters[$Environnement]['storageAccountName'] -ResourceGroupName $Parameters[$Environnement]['storageaccountresourcegroupname'] | out-null

    WriteLog "Bascule des informations ASG de toutes les VMs." -type INFO

    # Lancement du script de transfert (adapter le chemin si besoin)
    .\ASR_Offline_FailoverTransfertASG.ps1 -sid $Parameters[$Environnement]['SubscriptionId'] -RgPrimaire $resourceGroupName -RgDestination $ResourceGroupDestName -CustomFilePath $Parameters[$Environnement]['ContainerName']

  }
catch {
    WriteLog "$($Error[0])" -type ERROR
}

WriteLog "DONE - Reconfiguration terminée à partir des informations récupérées dans les fichiers JSON préalablement exportés." -type SUCCESS
