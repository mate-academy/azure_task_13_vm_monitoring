# task.ps1

$location = "polandcentral"
$resourceGroupName = "mate-azure-task-13"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"
$sshKeyPublicKey = (Get-Content -Raw "/root/.ssh/mate_azure_vm.pub").Trim() 
$publicIpAddressName = "linuxboxpip"
$vmName = "matebox"
$vmImage = "Ubuntu2204"
$vmSize = "Standard_B1s"
$dnsLabel = ("matetask{0}" -f (Get-Random -Minimum 10000 -Maximum 99999)).ToLower()
$adminUsername = "azureuser"
$plainPassword = "P@ss" + (Get-Random -Minimum 10000000 -Maximum 99999999) + "aA!"
$adminPassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPassword)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Invoke-WithRetry {
  param(
    [scriptblock]$Script,
    [int]$MaxAttempts = 4,
    [int]$DelaySeconds = 15
  )

  for ($i = 1; $i -le $MaxAttempts; $i++) {
    try {
      return & $Script
    } catch {
      Write-Warning "Attempt $i/$MaxAttempts failed: $($_.Exception.Message)"
      if ($i -eq $MaxAttempts) { throw }
      Start-Sleep -Seconds $DelaySeconds
    }
  }
} 

Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup -Name $resourceGroupName -Location $location

Write-Host "Creating a network security group $networkSecurityGroupName ..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH  -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow;
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP  -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow;
New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP

Write-Host "Creating a virtual network ..."
$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnet

Write-Host "Creating a SSH key ..."
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey

Write-Host "Creating a Public IP Address ..."

New-AzPublicIpAddress `
  -Name $publicIpAddressName `
  -ResourceGroupName $resourceGroupName `
  -Location $location `
  -Sku Standard `
  -AllocationMethod Static `
  -DomainNameLabel $dnsLabel
  
Write-Host "Creating a VM ..."
# Update the VM deployment command to enable a system-assigned mannaged identity on it. 

$vmParams = @{
  ResourceGroupName     = $resourceGroupName
  Name                  = $vmName
  Location              = $location
  Image                 = $vmImage
  Size                  = $vmSize
  SubnetName            = $subnetName
  VirtualNetworkName    = $virtualNetworkName
  SecurityGroupName     = $networkSecurityGroupName
  SshKeyName            = $sshKeyName
  PublicIpAddressName   = $publicIpAddressName
  Credential            = $cred
  SystemAssignedIdentity = $true
}

Invoke-WithRetry -Script { New-AzVm @vmParams }

Write-Host "Installing the TODO web app..."
$originUrl = (git remote get-url origin).Trim()

if ($originUrl -match 'github\.com[:/](?<user>[^/]+)/(?<repo>[^/]+?)(\.git)?$') {
  $gitUser = $Matches.user
  $gitRepo = $Matches.repo
} else {
  throw "Cannot parse origin URL: $originUrl"
}

# Требование обычно такое: ссылаться на main
$installScriptUrl = "https://raw.githubusercontent.com/$gitUser/$gitRepo/main/install-app.sh"

$params = @{
  ResourceGroupName  = $resourceGroupName
  VMName             = $vmName
  Location           = $location
  Name               = 'CustomScript'
  Publisher          = 'Microsoft.Azure.Extensions'
  ExtensionType      = 'CustomScript'
  TypeHandlerVersion = '2.1'
  Settings           = @{ fileUris = @($installScriptUrl) }
  ProtectedSettings  = @{ commandToExecute = "bash install-app.sh" }
  ForceRerun         = ([Guid]::NewGuid().ToString())
}

Set-AzVMExtension @params

# Install Azure Monitor Agent VM extention ->

Write-Host "Installing Azure Monitor Agent (AMA) ..."

# 1) Берём список версий AMA в регионе
$amaVersionFull = (Get-AzVMExtensionImage `
  -Location $location `
  -PublisherName "Microsoft.Azure.Monitor" `
  -Type "AzureMonitorLinuxAgent" |
  Sort-Object Version -Descending |
  Select-Object -First 1 -ExpandProperty Version)

if (-not $amaVersionFull) {
  throw "Cannot find AzureMonitorLinuxAgent extension versions in region $location"
}

# 2) Приводим версию к формату X.Y (часто Set-AzVMExtension принимает именно так)
$amaVersionFull = ($amaVersionFull -split '-')[0]   # убираем -preview если есть
$parts = $amaVersionFull -split '\.'

if ($parts.Count -lt 2) {
  throw "Unexpected AMA version format: $amaVersionFull"
}

$amaVersion = "$($parts[0]).$($parts[1])"

Write-Host "AMA version chosen: $amaVersion (raw: $amaVersionFull)"

# 3) Устанавливаем AMA с валидным typeHandlerVersion
Set-AzVMExtension `
  -Name "AzureMonitorLinuxAgent" `
  -ExtensionType "AzureMonitorLinuxAgent" `
  -Publisher "Microsoft.Azure.Monitor" `
  -ResourceGroupName $resourceGroupName `
  -VMName $vmName `
  -Location $location `
  -TypeHandlerVersion $amaVersion `
  -EnableAutomaticUpgrade $true `
  -ForceRerun ([Guid]::NewGuid().ToString()) `
  -Verbose | Out-Null

 
