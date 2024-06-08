$location = "uksouth"
$resourceGroupName = "mate-azure-task-13"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"
$sshKeyPublicKey = Get-Content "C:\Users\ipppk\.ssh\id_rsa.pub" -Raw
$publicIpAddressName = "linuxboxpip"
$vmName = "matebox"
$vmSize = "Standard_B1s"
$dnsLabel = "matetask" + (Get-Random -Count 1) 
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", (ConvertTo-SecureString "placeholderpassword" -AsPlainText -Force))

Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup -Name $resourceGroupName -Location $location

Write-Host "Creating a network security group $networkSecurityGroupName ..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow
$nsg = New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP

Write-Host "Creating a virtual network ..."
$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
$vnet = New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnet

Write-Host "Creating a SSH key ..."
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey

Write-Host "Creating a Public IP Address ..."
$publicIp = New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -Sku Basic -AllocationMethod Dynamic -DomainNameLabel $dnsLabel

Write-Host "Creating a network interface ..."
$nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $resourceGroupName -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $publicIp.Id -NetworkSecurityGroupId $nsg.Id

Write-Host "Creating a VM configuration ..."
$vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize | `
    Set-AzVMOperatingSystem -Linux -ComputerName $vmName -Credential $cred -DisablePasswordAuthentication | `
    Set-AzVMSourceImage -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" -Skus "22_04-lts-gen2" -Version "latest" | `
    Add-AzVMNetworkInterface -Id $nic.Id | `
    Add-AzVMSSHPublicKey -KeyData $sshKeyPublicKey -Path "/home/azureuser/.ssh/authorized_keys"

Write-Host "Creating a VM ..."
New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $vmConfig

# Перевірка, чи створена VM
$vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
if ($vm -eq $null) {
    Write-Host "VM was not created. Exiting script."
    exit 1
} else {
    Write-Host "VM created successfully."
}

Write-Host "Enabling system-assigned managed identity for the VM ..."
$vm.Identity = New-Object Microsoft.Azure.Management.Compute.Models.VirtualMachineIdentity -Property @{ Type = "SystemAssigned" }
Update-AzVM -ResourceGroupName $resourceGroupName -VM $vm

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

Write-Host "Installing Azure Monitor Agent VM extension"
$agentParams = @{
    ResourceGroupName = $resourceGroupName
    VMName = $vmName
    Name = "AzureMonitorLinuxAgent"
    Publisher = "Microsoft.Azure.Monitor"
    ExtensionType = "AzureMonitorLinuxAgent"
    TypeHandlerVersion = "1.0"
}
Set-AzVMExtension @agentParams
