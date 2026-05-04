$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if ([string]::IsNullOrEmpty($root)) { $root = (Get-Location).Path }

# README allows any region. Use centralus if uksouth hits B1s or Basic PIP quota (0) on this subscription.
$location = "centralus"
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
$vmSize = "Standard_B1s"
$dnsLabel = "matetask$(Get-Random -Maximum 999999)"
$dcrName = "mate-task13-dcr"
# After push, raw install script must be available for the CustomScript extension.
$installScriptUrl = "https://raw.githubusercontent.com/NazarKulyk6/azure_task_13_vm_monitoring/main/install-app.sh"
$dcrRuleFile = Join-Path $root "scripts/dcr-rule.json"

$sshPublicKeyPath = Join-Path $HOME ".ssh/id_ed25519.pub"
if (-not (Test-Path $sshPublicKeyPath)) {
    $sshPublicKeyPath = Join-Path $HOME ".ssh/id_rsa.pub"
}
$sshKeyPublicKey = Get-Content -Path $sshPublicKeyPath -Raw
$secPlain = ConvertTo-SecureString "N0tUsedForLogin!" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", $secPlain)

Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup -Name $resourceGroupName -Location $location

Write-Host "Creating a network security group $networkSecurityGroupName ..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH -Protocol Tcp -Direction Inbound -Priority 1001 `
    -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP -Protocol Tcp -Direction Inbound -Priority 1002 `
    -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow
$nsg = New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName `
    -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP

Write-Host "Creating a virtual network ..."
$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix -NetworkSecurityGroup $nsg
New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location `
    -AddressPrefix $vnetAddressPrefix -Subnet $subnet

Write-Host "Creating a SSH key ..."
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -Location $location -PublicKey $sshKeyPublicKey

Write-Host "Creating a Public IP (Standard+Static; Basic PIP often quota 0 on student subs) ..."
New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location `
    -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel

Write-Host "Creating a VM with system-assigned managed identity ..."
New-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Location $location -Image $vmImage -Size $vmSize `
    -SubnetName $subnetName -VirtualNetworkName $virtualNetworkName -SecurityGroupName $networkSecurityGroupName `
    -SshKeyName $sshKeyName -PublicIpAddressName $publicIpAddressName -Credential $cred -SystemAssignedIdentity

Write-Host "Installing the TODO web app (CustomScript) ..."
$csSettings = @{
    fileUris         = @($installScriptUrl)
    commandToExecute = "bash install-app.sh"
}
Set-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $vmName -Location $location -Name "CustomScript" `
    -Publisher "Microsoft.Azure.Extensions" -ExtensionType "CustomScript" -TypeHandlerVersion "2.1" -Settings $csSettings

Write-Host "Deploying Azure Monitor Agent (Linux) ..."
Set-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $vmName -Location $location -Name "AzureMonitorLinuxAgent" `
    -Publisher "Microsoft.Azure.Monitor" -ExtensionType "AzureMonitorLinuxAgent" -TypeHandlerVersion "1.29" -EnableAutomaticUpgrade

Write-Host "Creating Data Collection Rule (guest OS metrics) ..."
if (-not (Test-Path $dcrRuleFile)) { throw "Missing DCR rule file: $dcrRuleFile" }
az monitor data-collection rule create --resource-group $resourceGroupName --name $dcrName --location $location --kind Linux --rule-file $dcrRuleFile | Out-Null

$vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
$dcr = Get-AzDataCollectionRule -ResourceGroupName $resourceGroupName -Name $dcrName
$principalId = $vm.Identity.PrincipalId
if (-not $principalId) { throw "VM has no system-assigned identity principal id." }

Write-Host "Granting the VM identity access to the DCR (Monitoring Metrics Publisher) ..."
$role = Get-AzRoleDefinition -Name "Monitoring Metrics Publisher"
if ($null -eq (Get-AzRoleAssignment -ObjectId $principalId -Scope $dcr.Id -ErrorAction SilentlyContinue)) {
    New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionId $role.Id -Scope $dcr.Id
}

Write-Host "Associating the DCR with the VM ..."
$assocName = "ama-dcr-association"
az monitor data-collection rule association create --name $assocName --resource $vm.Id --rule-id $dcr.Id | Out-Null

$pip = Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $publicIpAddressName
Write-Host ""
Write-Host "Done. App: http://$($pip.DnsSettings.Fqdn):8080/api/"
Write-Host "Log check (after agent loads DCR, often 10–20 min): http://$($pip.DnsSettings.Fqdn):8080/static/files/azuremonitoragent/log/mdsd.info"
