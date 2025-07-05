param(
  [Parameter(Mandatory = $true)][string]$sid, #ex: 8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf, subscription id
  [Parameter(Mandatory = $true)][string]$RgName #ex: RG-test-asr
)

$ErrorActionPreference = "Stop"
Set-AzContext -SubscriptionId $sid | Out-Null

if(!(Test-Path $RgName))
{
  New-Item -ItemType Directory -Path $RgName | Out-Null
}

$VMs = Get-AzVM -ResourceGroupName $RgName
foreach($vm in $VMs)
{
  $FilePath = "$RgName\$($vm.name).json"
  Write-Output ""
  Write-Output "#####$($vm.name)#####"


  ###### Récupération des infos des cartes réseau de la VM à répliquer######
  $NicObjects = @()
  foreach ($VMNic in $vm.NetworkProfile.NetworkInterfaces)
  {
    $SplittedNicId = ($VMNic.Id).Split('/')
    $NicName = $SplittedNicId[-1]
    $NicResourceGroup = $SplittedNicId[4]
    $Nic = Get-AzNetworkInterface -Name $NicName -ResourceGroupName $NicResourceGroup
    $IpConfig = $Nic.IpConfigurations[0]
    $SplittedSubnetId = ($IpConfig.Subnet.id).Split('/')

    $AllASGs = @()
    # Make sure we have an array even if 0 or 1 item
    $IpConfig.ApplicationSecurityGroups | foreach-object {
      $AllASGs += $_.Id
    }

    $AllLBs =  @()
    # Make sure we have an array even if 0 or 1 item
    $IpConfig.LoadBalancerBackendAddressPools | foreach-object {
      $AllLBs += $_.Id
    }

    $Object = New-Object PSObject -Property @{
      VmName      = $vm.name
      NicName     = $NicName
      rg          = $NicResourceGroup
      ASGs        = $AllASGs
      LBs         = $AllLBs
      IsPrimary   = $Nic.Primary
      Vnet        = $SplittedSubnetId[8]
      Subnet      = $SplittedSubnetId[-1]
      IPV4Address = $IpConfig.PrivateIpAddress
    }

    $NicObjects += $Object
  }
  $NicObjects | ConvertTo-Json | Out-File $FilePath -Encoding UTF8
  Write-Host "done" -ForegroundColor Cyan
}
