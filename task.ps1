$location = "uksouth"
$resourceGroupName = "mate-azure-task-13"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"
# Исправлено на твой путь к ed25519
$sshKeyPublicKey = Get-Get-Content "$HOME/.ssh/id_ed25519.pub" 
$publicIpAddressName = "linuxboxpip"
$vmName = "matebox"
$vmImage = "Ubuntu2204"
# ВЕРНУЛ ОРИГИНАЛЬНЫЙ РАЗМЕР
$vmSize = "Standard_B1s"
$dnsLabel = "matetask" + (Get-Random -Count 1) 

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
# Оставляем Standard SKU для стабильности в uksouth
New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel

Write-Host "Creating a VM with Identity ..."
# Добавлен флаг -SystemAssignedIdentity
New-AzVm `
-ResourceGroupName $resourceGroupName `
-Name $vmName `
-Location $location `
-image $vmImage `
-size $vmSize `
-SubnetName $subnetName `
-VirtualNetworkName $virtualNetworkName `
-SecurityGroupName $networkSecurityGroupName `
-SshKeyName $sshKeyName -PublicIpAddressName $publicIpAddressName `
-SystemAssignedIdentity

Write-Host "Installing the TODO web app..."
$AppParams = @{
    ResourceGroupName  = $resourceGroupName
    VMName             = $vmName
    Name               = 'CustomScript'
    Publisher          = 'Microsoft.Azure.Extensions'
    ExtensionType      = 'CustomScript'
    TypeHandlerVersion = '2.1'
    Settings           = @{fileUris = @('https://raw.githubusercontent.com'); commandToExecute = './install-app.sh'}
}
Set-AzVMExtension @AppParams

Write-Host "Installing Azure Monitor Agent (AMA)..."
$AmaParams = @{
    ResourceGroupName  = $resourceGroupName
    VMName             = $vmName
    Name               = 'AzureMonitorLinuxAgent'
    Publisher          = 'Microsoft.Azure.Monitor'
    ExtensionType      = 'AzureMonitorLinuxAgent'
    # ОБНОВЛЕНО: Версия 1.30 (стабильная)
    TypeHandlerVersion = '1.30' 
    Location           = $location
}
Set-AzVMExtension @AmaParams

