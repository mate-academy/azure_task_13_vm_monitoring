<#
  Read First:
  1)  to see documentation for the commands below use:
      Get-Help $Your_CmdLet -Full
  2)  to see available values for specific parameters below use:
      Get-Help $Your_CmdLet -Parameter $Your_Parameter
  3)  to see the actual latest supported version of the
      CustomScript Extension - run:
      a) for Linux:
        Get-AzVMExtensionImage `
          -PublisherName Microsoft.Azure.Extensions `
          -Type CustomScript `
          -Location uksouth (or other location)
      b) fot Windows:
        Get-AzVMExtensionImage `
          -PublisherName Microsoft.Compute `
          -Type CustomScriptExtension `
          -Location uksouth (or other location)
      * You would get version output format x.x.x
        use version format x.x
  4)  This Template is designed for
        - creating separate NEW Resource Group
        - creating X count of VM's in the X count of AvailabilityCount
          with option to choose between Availability Zone / Set
        - SSH authentification
        - password still necessary for admin privilages
        - monitoring the OS-level metrics:
          for this:
          - ensure -IdentityType parameter is uncommented
          - ensure "AzureMonitorAgent" extension installation is uncommented
        - sequentional installation of different CustomScript extensions
          for this uncomment section "Removing Used Script Extension 'CustomScriptExtension'"
        - Cost-Free deploying in terms of Azure Free Account Subscription
          Therefore in case of Availability options chosen:
          - PublicIP settings & VMConfig section is commented
              Since "Basic" Sku parameter is deprecated
              within the Availability Zones
          - As a result of tht ^^ Regular connection from outside internet
              is not available
  5)  Set preferred settings below:
#>

# general settings:
$location =                   "uksouth"
$resourceGroupName =          "mate-azure-task-13"

# Network Security Group settings:
$networkSecurityGroupName =   "defaultnsg"

# Virtual Network settings:
$virtualNetworkName =         "vnet"
$subnetName =                 "default"
$vnetAddressPrefix =          "10.0.0.0/16"
$subnetAddressPrefix =        "10.0.0.0/24"

# public Ip settings:
# Optionally Use "label + (Get-Random -Count 1)" for dnsprefix
$publicIpAddressName =        "linuxboxpip"
$publicIpDnsprefix =          "mateacademyyegortask13"
$publicIpSku =                "Basic"
$publicIpAllocation =         "Dynamic"

# Network Interface settings:
$nicName =                    "NetInterface"
$ipConfigName =               "ipConfig1"

# SSH settings:
$sshKeyName =                 "linuxboxsshkey"
$sshKeyPublicKey =            Get-Content "~/.ssh/id_rsa.pub"

# VM settings:
$vmName =                     "matebox"
$vmSecurityType =             "Standard"
$vmSize =                     "Standard_B1s"

# Boot Diagnostic Storage Account settings
$bootStorageAccName =         "bootdiagnosstorageacc"
$bootStSkuName =              "Standard_LRS"
$bootStKind =                 "StorageV2"
$bootStAccessTier =           "Hot"
$bootStMinimumTlsVersion =    "TLS1_1"

# OS settings:
# manually configure Linux / Windows in "Set-AzVMOperatingSystem" section
$osUser =                     "yegor"
$osUserPassword =             "P@ssw0rd1234"
$osPublisherName =            "Canonical"
$osOffer =                    "0001-com-ubuntu-server-jammy"
$osSku =                      "22_04-lts-gen2"
$osVersion =                  "latest"
$osDiskSizeGB =               64
$osDiskType =                 "Premium_LRS"

<#
Availability Settings:
Adjust according to needed option:
  1) for Availability Zone
    - Comment 2 $availabilitySet references below
    - Comment "Creating Availability Set" section
    - Comment -AvailabilitySetId parameter
  2) for Avalability Set
    - Ensure 3 references below are uncommented
    - Ensure "Creating Availability Set" section is uncommented
    - Comment -Zone parameter
  3) No infrastructure redundancy required:
    - Comment 2 $availabilitySet references below
    - Comment "Creating Availability Set" section
    - Comment -AvailabilitySetId parameter
    - Comment -Zone parameter
    - Set $availabilityCounter for needed count of VM's to be deployed
#>
# $availabilitySetName =        "mateavalset"
# $availabilitySetFDcount =     2 # Max 3
$availabilityCounter =        1 # Max 20 for AvailabilitySet

Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup `
  -Name                       $resourceGroupName `
  -Location                   $location

Write-Host "Creating a network security group $networkSecurityGroupName ..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig `
  -Name                       SSH `
  -Protocol                   Tcp `
  -Direction                  Inbound `
  -Priority                   1001 `
  -SourceAddressPrefix        * `
  -SourcePortRange            * `
  -DestinationAddressPrefix   * `
  -DestinationPortRange       22 `
  -Access                     Allow
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig `
  -Name                       HTTP `
  -Protocol                   Tcp `
  -Direction                  Inbound `
  -Priority                   1002 `
  -SourceAddressPrefix        * `
  -SourcePortRange            * `
  -DestinationAddressPrefix   * `
  -DestinationPortRange       8080 `
  -Access                     Allow
New-AzNetworkSecurityGroup `
  -Name                       $networkSecurityGroupName `
  -ResourceGroupName          $resourceGroupName `
  -Location                   $location `
  -SecurityRules              $nsgRuleSSH, $nsgRuleHTTP
$networkSecurityGroupObj = Get-AzNetworkSecurityGroup `
  -Name                       $networkSecurityGroupName `
  -ResourceGroupName          $resourceGroupName

Write-Host "Creating a virtual network $virtualNetworkName ..."
$subnetConfig = New-AzVirtualNetworkSubnetConfig `
  -Name                       $subnetName `
  -AddressPrefix              $subnetAddressPrefix `
  -NetworkSecurityGroup       $networkSecurityGroupObj
New-AzVirtualNetwork `
  -Name                       $virtualNetworkName `
  -ResourceGroupName          $resourceGroupName `
  -Location                   $location `
  -AddressPrefix              $vnetAddressPrefix `
  -Subnet                     $subnetConfig
$vnetObj = Get-AzVirtualNetwork `
  -Name                       $virtualNetworkName `
  -ResourceGroupName          $resourceGroupName
$subnetId = $vnetObj.Subnets[0].Id

Write-Host "Creating an SSH key resource $sshKeyName ..."
New-AzSshKey `
  -Name                       $sshKeyName `
  -ResourceGroupName          $resourceGroupName `
  -PublicKey                  $sshKeyPublicKey

Write-Host "Creating Storage Account for boot diagnostic ..."
New-AzStorageAccount `
  -ResourceGroupName          $resourceGroupName `
  -Name                       $bootStorageAccName `
  -Location                   $location `
  -SkuName                    $bootStSkuName `
  -Kind                       $bootStKind `
  -AccessTier                 $bootStAccessTier `
  -MinimumTlsVersion          $bootStMinimumTlsVersion

# Write-Host "Creating Availability Set $availabilitySetName ..."
# New-AzAvailabilitySet `
#   -Location                   $location `
#   -Name                       $availabilitySetName `
#   -ResourceGroupName          $resourceGroupName `
#   -Sku                        aligned `
#   -PlatformFaultDomainCount   $availabilitySetFDcount `
#   -PlatformUpdateDomainCount  $availabilityCounter
# $AvailabilitySetObj = Get-AzAvailabilitySet `
#   -Name                       $availabilitySetName `
#   -ResourceGroupName          $resourceGroupName
# $AvailabilitySetID = $AvailabilitySetObj.Id

for ($i = 1; $i -le $availabilityCounter; $i++) {
  $AvailPublicIpName =       "${publicIpAddressName}${i}"
  $AvailPublicIpDnsprefix =  "${publicIpDnsprefix}${i}"
  Write-Host "Creating a Public IP $AvailPublicIpName ..."
  New-AzPublicIpAddress `
    -Name                     $AvailPublicIpName `
    -ResourceGroupName        $resourceGroupName `
    -Location                 $location `
    -Sku                      $publicIpSku `
    -AllocationMethod         $publicIpAllocation `
    -DomainNameLabel          $AvailPublicIpDnsprefix
    # -Zone                     $i  # for Availability Zone only
  $publicIpObj = Get-AzPublicIpAddress `
    -Name                     $AvailPublicIpName `
    -ResourceGroupName        $resourceGroupName

  $AvailNicName =            "${nicName}-forVM-${i}"
  $AvailIpConfigName =       "${ipConfigName}-forVM-${i}"
  Write-Host "Creating a Network Interface Configuration $AvailNicName ..."
  $ipConfig = New-AzNetworkInterfaceIpConfig `
    -Name                     $AvailIpConfigName `
    -SubnetId                 $subnetId `
    -PublicIpAddressId        $publicIpObj.Id
  New-AzNetworkInterface -Force `
    -Name                     $AvailNicName `
    -ResourceGroupName        $resourceGroupName `
    -Location                 $location `
    -IpConfiguration          $ipConfig
  $nicObj = Get-AzNetworkInterface `
    -Name                     $AvailNicName `
    -ResourceGroupName        $resourceGroupName

  Write-Host "Creating a Virtual Machine ..."
  $SecuredPassword = ConvertTo-SecureString `
    $osUserPassword -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential `
    ($osUser, $SecuredPassword)
  $AvailVmName =             "${vmName}-${i}"
  $vmconfig = New-AzVMConfig `
    -VMName                   $AvailVmName `
    -VMSize                   $vmSize `
    -SecurityType             $vmSecurityType `
    -IdentityType             SystemAssigned  # for exporting OS-level metrics to Azure Monitor
    # -AvailabilitySetId        $AvailabilitySetID
    # -Zone                     $i
  $vmconfig = Set-AzVMSourceImage `
    -VM                       $vmconfig `
    -PublisherName            $osPublisherName `
    -Offer                    $osOffer `
    -Skus                     $osSku `
    -Version                  $osVersion
  $vmconfig = Set-AzVMOSDisk `
    -VM                       $vmconfig `
    -Name                     "${vmName}-OSDisk-forVM-${i}" `
    -CreateOption             FromImage `
    -DeleteOption             Delete `
    -DiskSizeInGB             $osDiskSizeGB `
    -Caching                  ReadWrite `
    -StorageAccountType       $osDiskType
  $vmconfig = Set-AzVMOperatingSystem `
    -VM                       $vmconfig `
    -ComputerName             $vmName `
    -Linux                    `
    -Credential               $cred `
    -DisablePasswordAuthentication
  $vmconfig = Add-AzVMNetworkInterface `
    -VM                       $vmconfig `
    -Id                       $nicObj.Id
  $vmconfig = Set-AzVMBootDiagnostic `
    -VM                       $vmconfig `
    -Enable                   `
    -ResourceGroupName        $resourceGroupName `
    -StorageAccountName       $bootStorageAccName
  New-AzVM `
    -ResourceGroupName        $resourceGroupName `
    -Location                 $location `
    -VM                       $vmconfig `
    -SshKeyName               $sshKeyName

  $scriptUrl1 = "https://raw.githubusercontent.com/YegorVolkov/azure_task_13_vm_monitoring/dev/install-app.sh"
  $commandToExecute1 = "bash install-app.sh"

  Write-Host "Installing Script Extension 'CustomScriptExtension'"
  Set-AzVMExtension `
    -ResourceGroupName        $resourceGroupName `
    -VMName                   $AvailVmName `
    -Location                 $location `
    -Name                     "CustomScriptExtension" `
    -Publisher                "Microsoft.Azure.Extensions" `
    -ExtensionType            "CustomScript" `
    -TypeHandlerVersion       "2.1" `
    -Settings @{
        "fileUris" =          @($scriptUrl1)
        "commandToExecute" =  $commandToExecute1
    }
  while ($true) {
    $CustomScriptObj = Get-AzVMExtension `
      -ResourceGroupName      $resourceGroupName `
      -VMName                 $AvailVmName `
      -Name                   "CustomScriptExtension"
    $CustomScriptInstallStatus = $CustomScriptObj.ProvisioningState
    if ($CustomScriptInstallStatus -eq "Succeeded") {
        Write-Host "'CustomScriptExtension' installation succeeded"
        break
    }
    elseif ($CustomScriptInstallStatus -eq "Failed") {
        Write-Host "'CustomScriptExtension' installation failed"
        break
    }
    Write-Host "'CustomScriptExtension' installation still in progress"
    Start-Sleep -Seconds 10
  }
  # Write-Host "Removing Used Script Extension 'CustomScriptExtension'"
  # Remove-AzVMExtension `
  #   -ResourceGroupName        $resourceGroupName `
  #   -VMName                   $AvailVmName `
  #   -Name                     "CustomScriptExtension" `
  #   -Force
  # Write-Host "VM is ready for installation of next 'CustomScriptExtension'"
  Write-Host "Installing Script Extension 'Azure Monitor Agent'"
  Set-AzVMExtension `
    -Name                     "AzureMonitorAgent" `
    -ExtensionType            "AzureMonitorLinuxAgent" `
    -Publisher                "Microsoft.Azure.Monitor" `
    -ResourceGroupName        $resourceGroupName `
    -VMName                   $AvailVmName `
    -Location                 $location `
    -TypeHandlerVersion       "1.9" `
    -EnableAutomaticUpgrade   $true
}
