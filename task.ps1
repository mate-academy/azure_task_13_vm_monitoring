$location = "East US" 
$resourceGroupName = "mate-azure-task-13"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"
$sshKeyPublicKey = Get-Content "$HOME\.ssh\id_ed25519.pub" 
$publicIpAddressName = "linuxboxpip"
$vmName = "matebox"
$vmImage = "Ubuntu2204"
$vmSize = "Standard_E2_v4"
$dnsLabel = "matetask" + (Get-Random -Count 1) 
 
Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup -Name $resourceGroupName -Location $location
 
Write-Host "Creating a network security group $networkSecurityGroupName ..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH  -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow;
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP  -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow;
New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP
 
$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnet
 
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey
 
New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel
 
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
-SystemAssignedIdentity
 
# ↓↓↓ Write your code here ↓↓↓
 
$extensionName = "CustomScript"
$installScriptUrl = "https://raw.githubusercontent.com/Nicotqq/azure_task_12_deploy_app_with_vm_extention/main/install-app.sh"
$extensionVersion = "2.1"
 
Set-AzVMExtension `
    -ResourceGroupName $resourceGroupName `
    -VMName $vmName `
    -Name $extensionName `
    -Publisher "Microsoft.Azure.Extensions" `
    -ExtensionType "CustomScript" `
    -TypeHandlerVersion $extensionVersion `
    -Settings @{
        fileUris = @($installScriptUrl)
        commandToExecute = "bash install-app.sh"
    }
 
Set-AzVMExtension `
    -Name "AzureMonitorLinuxAgent" `
    -ExtensionType "AzureMonitorLinuxAgent" `
    -Publisher "Microsoft.Azure.Monitor" `
    -ResourceGroupName $resourceGroupName `
    -VMName $vmName `
    -Location $location `
    -TypeHandlerVersion "1.0" `
    -EnableAutomaticUpgrade $true