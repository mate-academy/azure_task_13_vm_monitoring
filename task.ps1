$location = "southafricanorth"
$resourceGroupName = "mate-azure-task-13"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"

# Перевірка та автоматичне створення SSH-ключа за потреби
$sshKeyPath = "$HOME/.ssh/id_rsa.pub"
if (-not (Test-Path $sshKeyPath)) {
    if (Test-Path "$HOME/.ssh/id_ed25519.pub") {
        $sshKeyPath = "$HOME/.ssh/id_ed25519.pub"
    } else {
        Write-Host "Створення нового SSH-ключа $sshKeyPath ..."
        New-Item -ItemType Directory -Path "$HOME/.ssh" -Force | Out-Null
        ssh-keygen -t rsa -b 2048 -f "$HOME/.ssh/id_rsa" -N '""'
    }
}
$sshKeyPublicKey = Get-Content $sshKeyPath -Raw

$publicIpAddressName = "linuxboxpip"
$vmName = "matebox"
$vmImage = "Ubuntu2204"
$vmSize = "Standard_B2as_v2"
$dnsLabel = "matetask" + (Get-Random -Minimum 100000 -Maximum 999999)

Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup -Name $resourceGroupName -Location $location

Write-Host "Creating a network security group $networkSecurityGroupName ..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow
New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP

Write-Host "Creating a virtual network $virtualNetworkName and subnet $subnetName ..."
$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnet

Write-Host "Creating SSH Key resource $sshKeyName ..."
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -Location $location -PublicKey $sshKeyPublicKey

Write-Host "Creating a Public IP Address $publicIpAddressName ..."
New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel

Write-Host "Creating a VM $vmName ..."
$secPassword = ConvertTo-SecureString "P@ssw0rd123456!" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", $secPassword)

New-AzVm `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -Name $vmName `
    -Image $vmImage `
    -Size $vmSize `
    -Credential $cred `
    -SubnetName $subnetName `
    -VirtualNetworkName $virtualNetworkName `
    -SecurityGroupName $networkSecurityGroupName `
    -SshKeyName $sshKeyName `
    -PublicIpAddressName $publicIpAddressName `
    -SystemAssignedIdentity

Write-Host "Installing the TODO web app..."
$Params = @{
    ResourceGroupName  = $resourceGroupName
    VMName             = $vmName
    Name               = 'CustomScript'
    Publisher          = 'Microsoft.Azure.Extensions'
    ExtensionType      = 'CustomScript'
    TypeHandlerVersion = '2.1'
    Settings          = @{fileUris = @('https://raw.githubusercontent.com/mate-academy/azure_task_13_vm_monitoring/main/install-app.sh'); commandToExecute = './install-app.sh'}
}
Set-AzVMExtension @Params

Write-Host "Installing Azure Monitor Agent extension..."
Set-AzVMExtension `
    -ResourceGroupName $resourceGroupName `
    -VMName $vmName `
    -Name "AzureMonitorLinuxAgent" `
    -Publisher "Microsoft.Azure.Monitor" `
    -ExtensionType "AzureMonitorLinuxAgent" `
    -TypeHandlerVersion "1.0"
