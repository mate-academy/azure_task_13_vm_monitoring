# Deploy a web app with OS-level monitoring

# Resource group and VM variables
$resourceGroupName = "mate-azure-task-13"
$location = "westeurope"
$vmName = "mateWebAppVM"
$publicIpDnsName = "matewebappvm" + (Get-Random -Minimum 1000 -Maximum 9999)

# Create resource group
New-AzResourceGroup -Name $resourceGroupName -Location $location

# Create subnet configuration
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name "mySubnet" -AddressPrefix 192.168.1.0/24

# Create virtual network
$vnet = New-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Location $location `
  -Name "myVNET" -AddressPrefix 192.168.0.0/16 -Subnet $subnetConfig

# Create public IP address
$pip = New-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Location $location `
  -Name "myPublicIP" -AllocationMethod Dynamic -DomainNameLabel $publicIpDnsName

# Create NSG and allow ports
$nsgRuleWeb = New-AzNetworkSecurityRuleConfig -Name "myNetworkSecurityGroupRuleWeb" -Protocol Tcp `
  -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 8080 -Access Allow

$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name "myNetworkSecurityGroupRuleSSH" -Protocol Tcp `
  -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 22 -Access Allow

$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location `
  -Name "myNetworkSecurityGroup" -SecurityRules $nsgRuleWeb, $nsgRuleSSH

# Create IP configuration
$ipConfig = New-AzNetworkInterfaceIpConfig -Name "myIpConfig" -Subnet $vnet.Subnets[0] `
  -PublicIpAddress $pip -PrivateIpAddressVersion IPv4

# Create network interface
$nic = New-AzNetworkInterface -Name "myNic" -ResourceGroupName $resourceGroupName `
  -Location $location -IpConfiguration $ipConfig -NetworkSecurityGroup $nsg

# Define a credential object
$securePassword = ConvertTo-SecureString "Azure123456!" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", $securePassword)

# Create virtual machine configuration with System Assigned Identity
$vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_B2s" | `
  Set-AzVMOperatingSystem -Linux -ComputerName $vmName -Credential $cred | `
  Set-AzVMSourceImage -PublisherName "Canonical" -Offer "UbuntuServer" -Skus "18.04-LTS" -Version "latest" | `
  Add-AzVMNetworkInterface -Id $nic.Id | `
  Set-AzVMMachineExtension -ExtensionName "AzureMonitorLinuxAgent" -Publisher "Microsoft.Azure.Monitor" `
  -TypeHandlerVersion "1.0" -Settings @{} -ProtectedSettings @{} | `
  Set-AzVMIdentity -SystemAssignedIdentity

# Create the virtual machine
New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $vmConfig

# Install web app using custom script extension
Set-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $vmName -Name "webAppDeployment" `
  -Publisher "Microsoft.Azure.Extensions" -ExtensionType "CustomScript" -TypeHandlerVersion "2.0" `
  -SettingString '{
    "fileUris": ["https://raw.githubusercontent.com/Yevgene-DP/azure_task_13_vm_monitoring/main/install-app.sh"],
    "commandToExecute": "bash install-app.sh"
  }'

# Get public IP address
$ip = Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name "myPublicIP"

Write-Output "Web app deployed successfully!"
Write-Output "Access your web app at: http://$($ip.DnsSettings.Fqdn):8080"
Write-Output "VM name: $vmName"
Write-Output "Resource Group: $resourceGroupName"