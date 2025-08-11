# Параметри
$location = "uksouth"
$resourceGroupName = "mate-azure-task-13"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"
$sshKeyPublicKey = Get-Content "~/.ssh/id_rsa.pub"

$publicIpAddressNamePrefix = "linuxboxpip"
$vmNamePrefix = "matebox"
$vmImage = "UbuntuLTS"
$vmSize = "Standard_B1s"
$dnsLabelPrefix = "matetask"

$vmCount = 3
$githubUsername = "mate-academy"

# Створення NSG і мережі (поза циклом)
Write-Host "Creating network security group $networkSecurityGroupName ..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow
New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP

$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnet

# Створення SSH ключа
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey

# === Data Collection Rule (DCR) ===

# ВАЖЛИВО: Переконайтесь, що у вас є Log Analytics workspace з ім’ям mateWorkspace
# Якщо ні — створіть його вручну або додайте код для створення

$workspaceResourceId = "/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/mateWorkspace"

$dcrName = "mateDCR"
$dcrDescription = "Data Collection Rule for OS-level metrics"

$dcrDataSources = @{
    performanceCounters = @(
        @{ counterSpecifier = "\\Processor(_Total)\\% Processor Time"; samplingFrequencyInSeconds = 15 }
        @{ counterSpecifier = "\\Memory\\Available MBytes"; samplingFrequencyInSeconds = 15 }
        @{ counterSpecifier = "\\LogicalDisk(_Total)\\% Free Space"; samplingFrequencyInSeconds = 15 }
    )
}

$dcrDestinations = @{
    logAnalytics = @{
        workspaceResourceId = $workspaceResourceId
    }
}

if (-not (Get-AzDataCollectionRule -ResourceGroupName $resourceGroupName -Name $dcrName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating Data Collection Rule $dcrName ..."
    New-AzDataCollectionRule -ResourceGroupName $resourceGroupName -Name $dcrName `
        -Location $location `
        -DataSources $dcrDataSources `
        -Destinations $dcrDestinations `
        -Description $dcrDescription
} else {
    Write-Host "Data Collection Rule $dcrName already exists."
}

# Отримуємо об'єкт DCR для подальшого використання
$dcr = Get-AzDataCollectionRule -ResourceGroupName $resourceGroupName -Name $dcrName

$results = @()

for ($i=1; $i -le $vmCount; $i++) {
    $vmName = "$vmNamePrefix$i"
    $publicIpAddressName = "$publicIpAddressNamePrefix$i"
    $dnsLabel = "$dnsLabelPrefix$i$(Get-Random -Maximum 9999)"

    Write-Host "Creating public IP $publicIpAddressName with DNS label $dnsLabel ..."
    New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel

    Write-Host "Creating VM $vmName with System Assigned Identity..."
    New-AzVm `
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
        -SystemAssignedIdentity

    $scriptUri = "https://raw.githubusercontent.com/$githubUsername/azure_task_13_vm_monitoring/main/install-app.sh"

    $params = @{
        ResourceGroupName = $resourceGroupName
        VMName = $vmName
        Name = 'CustomScript'
        Publisher = 'Microsoft.Azure.Extensions'
        ExtensionType = 'CustomScript'
        TypeHandlerVersion = '2.1'
        Settings = @{
            fileUris = @($scriptUri);
            commandToExecute = './install-app.sh'
        }
    }
    Write-Host "Setting CustomScript extension on $vmName ..."
    Set-AzVMExtension @params

    # Отримуємо VM для отримання ID
    $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName

    # Асоціація DCR з VM
    Write-Host "Associating Data Collection Rule $dcrName with VM $vmName ..."
    New-AzDataCollectionRuleAssociation -ResourceGroupName $resourceGroupName `
        -Name "${vmName}DcrAssociation" `
        -DataCollectionRuleId $dcr.Id `
        -Scope $vm.Id

    $publicIp = Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $publicIpAddressName

    $results += [PSCustomObject]@{
        VMName = $vmName
        PublicIpAddress = $publicIp.IpAddress
        DnsName = $publicIp.DnsSettings.Fqdn
    }
}

# Записуємо у result.json
$results | ConvertTo-Json -Depth 3 | Out-File -FilePath "./result.json" -Encoding utf8
Write-Host "Saved deployment info to result.json"
