Import-Module -Name Az.Compute -Force

$location = "ukwest"
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
$vmImage = "Ubuntu2204"
$vmSize = "Standard_B1s"
$dnsLabel = "matetask" + (Get-Random -Count 1)

Write-Host "Створення групи ресурсів $resourceGroupName ..."
New-AzResourceGroup -Name $resourceGroupName -Location $location

Write-Host "Створення групи безпеки мережі $networkSecurityGroupName ..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH  -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP  -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow
New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP

Write-Host "Створення віртуальної мережі ..."
$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnet

Write-Host "Створення SSH-ключа ..."
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey

Write-Host "Creating a Public IP Address ..."
New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel

Write-Host "Створення віртуальної машини ..."
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

# Очікування появи ВМ у ресурсній групі
Write-Host "Очікування створення ВМ..."
do {
    Start-Sleep -Seconds 10
    $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Host "ВМ ще не створена..."
    }
} while (-not $vm)

# Після цього — очікування запуску ВМ
Write-Host "Очікування готовності ВМ (PowerState/running)..."
do {
    Start-Sleep -Seconds 10
    $vmStatus = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Status
    $state = $vmStatus.Statuses | Where-Object { $_.Code -like "PowerState*" } | Select-Object -ExpandProperty Code -First 1
    if (-not $state) {
        $state = "Unknown"
    }
    Write-Host "Стан ВМ: $state"
} while ($state -ne "PowerState/running")

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

Write-Host "Встановлення агента Azure Monitor..."
$amaParams = @{
    ResourceGroupName  = $resourceGroupName
    VMName             = $vmName
    Name               = 'AzureMonitorLinuxAgent'
    Publisher          = 'Microsoft.Azure.Monitor'
    ExtensionType      = 'AzureMonitorLinuxAgent'
    TypeHandlerVersion = '1.29'
    EnableAutomaticUpgrade = $true
}
Set-AzVMExtension @amaParams