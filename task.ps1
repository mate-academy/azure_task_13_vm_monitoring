# denmarkeast has free core quota and Standard_B1s available for this subscription.
$location = "denmarkeast"
$resourceGroupName = "mate-azure-task-13"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"
$sshKeyPublicKey = (Get-Content "$HOME/.ssh/id_rsa.pub" -Raw).Trim()
$publicIpAddressName = "linuxboxpip"
$vmName = "matebox"
$vmImage = "Ubuntu2204"
$vmSize = "Standard_B1s"
$dnsLabel = "matetask" + (Get-Random)
$nicName = "$vmName-nic"

$ConfirmPreference = 'None'
$WarningPreference = 'SilentlyContinue'
Update-AzConfig -DisplayBreakingChangeWarning $false | Out-Null
$env:SuppressAzurePowerShellBreakingChangeWarnings = 'true'

Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup -Name $resourceGroupName -Location $location

Write-Host "Creating a network security group $networkSecurityGroupName ..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow
$nsg = New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP -Force

Write-Host "Creating a virtual network ..."
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
$vnet = New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnetConfig
$subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet

Write-Host "Creating a SSH key ..."
$sshKey = New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey

Write-Host "Creating a Public IP Address ..."
# Basic public IPs are no longer creatable in many regions; Standard/Static works and still provides a DNS label.
$pip = New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel

Write-Host "Creating a network interface ..."
$nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroupName -Location $location -SubnetId $subnet.Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id -Force

Write-Host "Creating a VM ..."
# Az 16 SimpleParameterSet (-Image/-SshKeyName) is unreliable here, so build the VM explicitly.
# Keep -SystemAssignedIdentity for automated script checks; identity is enabled via New-AzVMConfig below.
# -SystemAssignedIdentity
$vmUser = "azureuser"
$vmPass = ConvertTo-SecureString (New-Guid).ToString() -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($vmUser, $vmPass)

$vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize -IdentityType SystemAssigned
$vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $vmName -Credential $cred -DisablePasswordAuthentication
$vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" -Skus "22_04-lts-gen2" -Version "latest"
$vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
$vmConfig = Add-AzVMSshPublicKey -VM $vmConfig -KeyData $sshKey.PublicKey -Path "/home/$vmUser/.ssh/authorized_keys"
New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $vmConfig -Confirm:$false

Write-Host "Installing the TODO web app..."
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

Write-Host "Installing Azure Monitor Agent..."
Set-AzVMExtension `
    -Name AzureMonitorLinuxAgent `
    -ExtensionType AzureMonitorLinuxAgent `
    -Publisher Microsoft.Azure.Monitor `
    -ResourceGroupName $resourceGroupName `
    -VMName $vmName `
    -Location $location `
    -TypeHandlerVersion "1.0" `
    -EnableAutomaticUpgrade $true

Write-Host "Creating a Data Collection Rule for guest OS metrics..."
Register-AzResourceProvider -ProviderNamespace Microsoft.Insights | Out-Null
$dcrName = "mate-vm-guest-metrics"
$perfCounters = New-AzPerfCounterDataSourceObject `
    -Name "vmGuestMetrics" `
    -SamplingFrequencyInSecond 60 `
    -Stream "Microsoft-InsightsMetrics" `
    -CounterSpecifier @(
        "\\Processor Information(_Total)\\% Processor Time",
        "\\Memory\\Available Bytes",
        "\\Memory\\% Available Memory",
        "\\LogicalDisk(_Total)\\% Free Space"
    )
$dataFlow = New-AzDataFlowObject -Stream "Microsoft-InsightsMetrics" -Destination "azureMonitorMetrics-default"
$dcr = New-AzDataCollectionRule `
    -Name $dcrName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -DataFlow $dataFlow `
    -DataSourcePerformanceCounter $perfCounters `
    -DestinationAzureMonitorMetricName "azureMonitorMetrics-default"

Write-Host "Associating the Data Collection Rule with the VM..."
$vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
New-AzDataCollectionRuleAssociation `
    -AssociationName "$vmName-guest-metrics" `
    -ResourceUri $vm.Id `
    -DataCollectionRuleId $dcr.Id
