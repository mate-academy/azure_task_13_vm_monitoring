$location = "southafricanorth"
$location = "uksouth"
$resourceGroupName = "mate-azure-task-13"
$vmName = "matebox"
$vmSize = "Standard_B1s"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"
$sshKeyPublicKey = Get-Content "~/.ssh/id_rsa.pub"
$publicIpAddressName = "linuxboxpip"
$dnsLabel = "matetask-d4vp-" + (Get-Random -Minimum 1000 -Maximum 9999)

Write-Host "Creating Resource Group in $location..."
New-AzResourceGroup -Name $resourceGroupName -Location $location -Force

Write-Host "Creating Network..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow
New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP

$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnet

$pip = New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel

Write-Host "Creating SSH Key..."
if (!(Get-AzSshKey -ResourceGroupName $resourceGroupName -Name $sshKeyName -ErrorAction SilentlyContinue)) {
    New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey
}

Write-Host "Creating VM ($vmSize - ARM64)..."
New-AzVm `
-ResourceGroupName $resourceGroupName `
-Name $vmName `
-Location $location `
-Image "Ubuntu2204" `
-Size $vmSize `
-SubnetName $subnetName `
-VirtualNetworkName $virtualNetworkName `
-SecurityGroupName $networkSecurityGroupName `
-SshKeyName $sshKeyName `
-PublicIpAddressName $publicIpAddressName `
-SystemAssignedIdentity

Write-Host "Installing App..."
$Params = @{
    ResourceGroupName  = $resourceGroupName
    VMName             = $vmName
    Name               = 'CustomScript'
    Publisher          = 'Microsoft.Azure.Extensions'
    ExtensionType      = 'CustomScript'
    TypeHandlerVersion = '2.1'
    Settings           = @{fileUris = @('https://raw.githubusercontent.com/mate-academy/azure_task_13_vm_monitoring/main/install-app.sh'); commandToExecute = './install-app.sh'}
}
Set-AzVMExtension @Params

Write-Host "Creating Data Collection Rule structure..."

$dest = New-AzDataCollectionRuleDestinationObject -AzureMonitorMetric @{Name="azureMonitorMetrics"}

$perfCounters = @("\\Processor(_Total)\\% Processor Time", "\\Memory\\Available MBytes", "\\LogicalDisk(_Total)\\% Free Space")
$source = New-AzDataCollectionRuleDataSourceObject -PerformanceCounter @{
    Name="LinuxCounters"
    Streams="Microsoft-InsightsMetrics"
    SamplingFrequencyInSeconds=60
    CounterSpecifiers=$perfCounters
}

$flow = New-AzDataCollectionRuleDataFlowObject -Destinations "azureMonitorMetrics" -Streams "Microsoft-InsightsMetrics"

New-AzDataCollectionRule -Location $location -ResourceGroupName $resourceGroupName -Name "mate-dcr" -DataSources $source -Destinations $dest -DataFlows $flow

Write-Host "Associating DCR with VM..."
$vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
New-AzDataCollectionRuleAssociation -TargetResourceId $vm.Id -DataCollectionRuleId "/subscriptions/$(Get-AzContext | Select-Object -ExpandProperty Subscription | Select-Object -ExpandProperty Id)/resourceGroups/$resourceGroupName/providers/Microsoft.Insights/dataCollectionRules/mate-dcr" -Name "mate-dcr-association"