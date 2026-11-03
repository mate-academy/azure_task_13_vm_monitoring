$location = "switzerlandnorth"
$resourceGroupName = "mate-azure-task-13"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"
$publicIpAddressName = "linuxboxpip"
$vmName = "matebox"
$vmImage = "Ubuntu2204"
$vmSize = "Standard_B2ats_v2"
$dnsLabel = "matetask" + (Get-Random -Count 1)
$dcrName = "mate-linux-dcr"

$localKeyPath = "$HOME\.ssh\matebox_task13_key"
if (-not (Test-Path "$localKeyPath.pub")) {
    ssh-keygen -t rsa -b 2048 -f $localKeyPath -N '""'
}
$sshKeyPublicKey = Get-Content "$localKeyPath.pub" -Raw

New-AzResourceGroup -Name $resourceGroupName -Location $location -Force

$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow
New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP -Force

$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnet -Force

New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey

New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel -Force

$cred = New-Object System.Management.Automation.PSCredential ("azureuser", (ConvertTo-SecureString "IgnoreThisPassword123!" -AsPlainText -Force))

New-AzVm `
    -ResourceGroupName $resourceGroupName `
    -Name $vmName `
    -Location $location `
    -image $vmImage `
    -size $vmSize `
    -SubnetName $subnetName `
    -VirtualNetworkName $virtualNetworkName `
    -SecurityGroupName $networkSecurityGroupName `
    -SshKeyName $sshKeyName `
    -PublicIpAddressName $publicIpAddressName `
    -Credential $cred `
    -SystemAssignedIdentity

$Params = @{
    ResourceGroupName  = $resourceGroupName
    VMName             = $vmName
    Name               = 'CustomScript'
    Publisher          = 'Microsoft.Azure.Extensions'
    ExtensionType      = 'CustomScript'
    TypeHandlerVersion = '2.1'
    Settings           = @{fileUris = @('https://raw.githubusercontent.com/mate-academy/azure_task_13_vm_monitoring/main/install-app.sh'); commandToExecute = 'bash install-app.sh'}
}
Set-AzVMExtension @Params

$amaParams = @{
    ResourceGroupName      = $resourceGroupName
    VMName                 = $vmName
    Name                   = 'AzureMonitorLinuxAgent'
    Publisher              = 'Microsoft.Azure.Monitor'
    ExtensionType          = 'AzureMonitorLinuxAgent'
    TypeHandlerVersion     = '1.25'
    EnableAutomaticUpgrade = $true
}
Set-AzVMExtension @amaParams

$dcrJson = @"
{
  "location": "$location",
  "kind": "Linux",
  "properties": {
    "dataSources": {
      "performanceCounters": [
        {
          "name": "perfCounterDataSource60",
          "streams": [
            "Microsoft-InsightsMetrics"
          ],
          "samplingFrequencyInSeconds": 60,
          "counterSpecifiers": [
            "Processor(*)\\% Processor Time",
            "Memory(*)\\% Used Memory",
            "Memory(*)\\Available MBytes Memory",
            "LogicalDisk(*)\\% Free Space"
          ]
        }
      ]
    },
    "destinations": {
      "azureMonitorMetrics": {
        "name": "azureMonitorMetrics-default"
      }
    },
    "dataFlows": [
      {
        "streams": [
          "Microsoft-InsightsMetrics"
        ],
        "destinations": [
          "azureMonitorMetrics-default"
        ]
      }
    ]
  }
}
"@

$dcr = New-AzDataCollectionRule -ResourceGroupName $resourceGroupName -Name $dcrName -JsonString $dcrJson
$vmResource = Get-AzVm -ResourceGroupName $resourceGroupName -Name $vmName
New-AzDataCollectionRuleAssociation -TargetResourceId $vmResource.Id -AssociationName "matebox-dcr-assoc" -DataCollectionRuleId $dcr.Id