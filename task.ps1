$location = "denmarkeast"
$resourceGroupName = "mate-azure-task-13"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"
$sshKeyPublicKey = Get-Content "~/.ssh/id_rsa.pub"
$publicIpAddressName = "linuxboxpip"
$vmName = "matebox"
$vmImage = "Ubuntu2404"
$vmSize = "Standard_B2ats_v2"
$dnsLabel = "prostoponchik-matebox-13"
$vmAdminUsername = "ponchik"

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
New-AzVM `
    -ResourceGroupName $resourceGroupName `
    -Name $vmName `
    -Location $location `
    -Image $vmImage `
    -Size $vmSize `
    -SubnetName $subnetName `
    -VirtualNetworkName $virtualNetworkName `
    -SecurityGroupName $networkSecurityGroupName `
    -SshKeyName $sshKeyName `
    -PublicIpAddressName $publicIpAddressName `
    -SystemAssignedIdentity `
    -Credential (
    New-Object System.Management.Automation.PSCredential(
        $vmAdminUsername,
        (New-Object System.Security.SecureString)
    )
)

Write-Host "Installing the TODO web app..."
$Params = @{
    ResourceGroupName  = $resourceGroupName
    VMName             = $vmName
    Name               = 'CustomScript'
    Publisher          = 'Microsoft.Azure.Extensions'
    ExtensionType      = 'CustomScript'
    TypeHandlerVersion = '2.1'
    Settings           = @{fileUris = @('https://raw.githubusercontent.com/prostoponchik/azure_task_13_vm_monitoring/main/install-app.sh'); commandToExecute = './install-app.sh' }
}

Set-AzVMExtension @Params

# Install Azure Monitor Agent VM extention ->
Write-Host "Installing Azure Monitor Agent VM extension..."
$Params = @{
    ResourceGroupName      = $resourceGroupName
    VMName                 = $vmName
    Name                   = 'AzureMonitorLinuxAgent'
    Publisher              = 'Microsoft.Azure.Monitor'
    ExtensionType          = 'AzureMonitorLinuxAgent'
    TypeHandlerVersion     = '1.0'
    EnableAutomaticUpgrade = $true
}

Set-AzVMExtension @Params

Write-Host "Creating a Data Collection Rule (DCR) for the VM..."
# Create performance counter source
$perfCounters = New-AzPerfCounterDataSourceObject `
    -Name "linuxPerfCounters" `
    -Stream "Microsoft-InsightsMetrics" `
    -SamplingFrequencyInSecond 60 `
    -CounterSpecifier @(
    "Processor(*)\% Processor Time",
    "Memory(*)\% Used Memory",
    "Logical Disk(*)\% Used Space",
    "Network(*)\Total Bytes"
)

# Route metrics to Azure Monitor
$dataFlow = New-AzDataFlowObject `
    -Stream "Microsoft-InsightsMetrics" `
    -Destination "azureMonitorMetrics-default"

# Create DCR
$dcr = New-AzDataCollectionRule `
    -Name "vm-guest-metrics-dcr" `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -DataSourcePerformanceCounter $perfCounters `
    -DataFlow $dataFlow `
    -DestinationAzureMonitorMetricName "azureMonitorMetrics-default"

Write-Host "Associating the DCR with the VM..."
# Associate DCR with VM
$vm = Get-AzVM `
    -ResourceGroupName $resourceGroupName `
    -Name $vmName

Write-Host "VM ID: $($vm.Id)"
New-AzDataCollectionRuleAssociation `
    -AssociationName "vm-guest-metrics-association" `
    -ResourceUri $vm.Id `
    -DataCollectionRuleId $dcr.Id

    