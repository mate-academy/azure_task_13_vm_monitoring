$ErrorActionPreference = "Stop"

# Main configuration
$location = "indiasouthcentral"
$resourceGroupName = "mate-azure-task-13"

# Network configuration
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"

$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"

# SSH configuration
$sshKeyName = "linuxboxsshkey"
$sshPublicKeyPath = Join-Path $HOME ".ssh/vm-demo-key.pub"

# Public IP configuration
$publicIpAddressName = "linuxboxpip"
$dnsLabel = "matetask13-aleksandrmajlo-" +
    (Get-Random -Minimum 10000 -Maximum 99999)

# VM configuration
$vmName = "matebox"
$adminUsername = "azureuser"
$vmImage = "Ubuntu2204"
$vmSize = "Standard_B1s"

# Application installation script
$installScriptUrl = `
    "https://raw.githubusercontent.com/aleksandrmajlo/azure_task_13_vm_monitoring/azure-majlo/install-app.sh"

if (-not (Test-Path $sshPublicKeyPath)) {
    throw "SSH public key was not found: $sshPublicKeyPath"
}

$sshKeyPublicKey = (Get-Content $sshPublicKeyPath -Raw).Trim()

# Create resource group
Write-Host "Creating resource group $resourceGroupName ..."

New-AzResourceGroup `
    -Name $resourceGroupName `
    -Location $location

# Create NSG rules
Write-Host "Creating network security group ..."

$nsgRuleSSH = New-AzNetworkSecurityRuleConfig `
    -Name "SSH" `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1001 `
    -SourceAddressPrefix "*" `
    -SourcePortRange "*" `
    -DestinationAddressPrefix "*" `
    -DestinationPortRange 22 `
    -Access Allow

$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig `
    -Name "HTTP" `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1002 `
    -SourceAddressPrefix "*" `
    -SourcePortRange "*" `
    -DestinationAddressPrefix "*" `
    -DestinationPortRange 8080 `
    -Access Allow

$nsg = New-AzNetworkSecurityGroup `
    -Name $networkSecurityGroupName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -SecurityRules $nsgRuleSSH, $nsgRuleHTTP

# Create VNet and subnet
Write-Host "Creating virtual network ..."

$subnet = New-AzVirtualNetworkSubnetConfig `
    -Name $subnetName `
    -AddressPrefix $subnetAddressPrefix

New-AzVirtualNetwork `
    -Name $virtualNetworkName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -AddressPrefix $vnetAddressPrefix `
    -Subnet $subnet

# Create Azure SSH key resource
Write-Host "Creating SSH key resource ..."

New-AzSshKey `
    -Name $sshKeyName `
    -ResourceGroupName $resourceGroupName `
    -PublicKey $sshKeyPublicKey

# Create Public IP
Write-Host "Creating public IP ..."

New-AzPublicIpAddress `
    -Name $publicIpAddressName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -Sku "Standard" `
    -AllocationMethod "Static" `
    -DomainNameLabel $dnsLabel

# Credential object required by New-AzVM
$securePassword = ConvertTo-SecureString `
    ("Azure!" + [guid]::NewGuid().ToString("N")) `
    -AsPlainText `
    -Force

$credential = [PSCredential]::new(
    $adminUsername,
    $securePassword
)

# Create VM with system-assigned managed identity
Write-Host "Creating VM with system-assigned identity ..."

New-AzVM `
    -ResourceGroupName $resourceGroupName `
    -Name $vmName `
    -Location $location `
    -Image $vmImage `
    -Size $vmSize `
    -Credential $credential `
    -VirtualNetworkName $virtualNetworkName `
    -SubnetName $subnetName `
    -SecurityGroupName $networkSecurityGroupName `
    -PublicIpAddressName $publicIpAddressName `
    -SshKeyName $sshKeyName `
    -SystemAssignedIdentity `
    -SecurityType "Standard"

# Install todo application with Custom Script Extension
Write-Host "Installing todo application ..."

$customScriptSettings = @{
    fileUris = @(
        $installScriptUrl
    )
    commandToExecute = "bash install-app.sh"
}

Set-AzVMExtension `
    -ResourceGroupName $resourceGroupName `
    -VMName $vmName `
    -Location $location `
    -Name "CustomScript" `
    -Publisher "Microsoft.Azure.Extensions" `
    -ExtensionType "CustomScript" `
    -TypeHandlerVersion "2.1" `
    -Settings $customScriptSettings

# Install Azure Monitor Agent
Write-Host "Installing Azure Monitor Linux Agent ..."

Set-AzVMExtension `
    -ResourceGroupName $resourceGroupName `
    -VMName $vmName `
    -Location $location `
    -Name "AzureMonitorLinuxAgent" `
    -Publisher "Microsoft.Azure.Monitor" `
    -ExtensionType "AzureMonitorLinuxAgent" `
    -TypeHandlerVersion "1.0" `
    -EnableAutomaticUpgrade $true

$publicIp = Get-AzPublicIpAddress `
    -ResourceGroupName $resourceGroupName `
    -Name $publicIpAddressName

Write-Host ""
Write-Host "VM and monitoring agent deployment completed."
Write-Host "Application: http://$($publicIp.DnsSettings.Fqdn):8080"