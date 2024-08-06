param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
    [bool]$DownloadArtifacts=$true
)


# default script values 
$taskName = "task13"

$artifactsConfigPath = "$PWD/artifacts.json"
$resourcesTemplateName = "exported-template.json"
$tempFolderPath = "$PWD/temp"

if ($DownloadArtifacts) { 
    Write-Output "Reading config"
    $artifactsConfig = Get-Content -Path $artifactsConfigPath | ConvertFrom-Json

    Write-Output "Checking if temp folder exists"
    if (-not (Test-Path "$tempFolderPath")) { 
        Write-Output "Temp folder does not exist, creating..."
        New-Item -ItemType Directory -Path $tempFolderPath
    }

    Write-Output "Downloading artifacts"

    if (-not $artifactsConfig.resourcesTemplate) { 
        throw "Artifact config value 'resourcesTemplate' is empty! Please make sure that you executed the script 'scripts/generate-artifacts.ps1', and commited your changes"
    } 
    Invoke-WebRequest -Uri $artifactsConfig.resourcesTemplate -OutFile "$tempFolderPath/$resourcesTemplateName" -UseBasicParsing

}

Write-Output "Validating artifacts"
$TemplateFileText = [System.IO.File]::ReadAllText("$tempFolderPath/$resourcesTemplateName")
$TemplateObject = ConvertFrom-Json $TemplateFileText -AsHashtable

$nsg = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Network/networkSecurityGroups")
if ($nsg) {
    if ($nsg.name.Count -eq 1) { 
        Write-Output "`u{2705} Checked if the Network Security Group resource exists - OK"
    }  else {
        Write-Output `u{1F914}
        throw "More than one Network Security Group resource was found in the task resource group. Please make sure that your script creates only one network security group (check if script attaches the NSG you are creating to the subnet) and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find Network Security Group resouce. Please re-deploy the VM and try again."
}

$virtualNetwork = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Network/virtualNetworks" )
if ($virtualNetwork ) {
    if ($virtualNetwork.name.Count -eq 1) { 
        Write-Output "`u{2705} Checked if virtual network exists - OK."
    }  else {
        Write-Output `u{1F914}
        throw "More than one virtual network resource was found in the task resource group. Please make sure that your script deploys only 1 virtual network, and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find virtual network in the task resource group. Please make sure that your script creates a virtual network and try again."
}

$virtualNetworkName = $virtualNetwork.name.Replace("[parameters('virtualNetworks_", "").Replace("_name')]", "")
if ($virtualNetworkName -eq "vnet") { 
    Write-Output "`u{2705} Checked the virtual network name - OK."
} else {
    Write-Output `u{1F914}
    throw "Unable to verify the virtual network name. Please make sure that your script creates a virtual network called 'vnet' and try again."
}

$subnet = $virtualNetwork.properties.subnets
if ($subnet) {
    if ($subnet.name.Count -eq 1) { 
        Write-Output "`u{2705} Checked if subnet exists - OK."
    }  else {
        Write-Output `u{1F914}
        throw "More than one subnet was found in the virtual network. Please make sure that your script deploys only 1 subnet, and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find subnet in the virtual network. Please make sure that your script creates a subnet and try again."
}

if ($subnet.name -eq "default") { 
    Write-Output "`u{2705} Checked the subnet name - OK."
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify the subnet name. Please make sure that your script creates a subnet called 'default' and try again."
}

$pip = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Network/publicIPAddresses")
if ($pip) {
    if ($pip.name.Count -eq 1) { 
        Write-Output "`u{2705} Checked if the Public IP resource exists - OK"
    }  else { 
        Write-Output `u{1F914}
        throw "More than one Public IP resource was found in the VM resource group. Please make sure that your script creates only one public IP resource and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find Public IP address resouce. Please make sure that your script creates a Public IP resouce (Basic SKU, dynamic IP allocation) and try again."
}

if ($pip.properties.dnsSettings.domainNameLabel) { 
    Write-Output "`u{2705} Checked the Public IP DNS label - OK"
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify the Public IP DNS label. Please create the DNS label for your public IP and try again."
}

$sshKey = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Compute/sshPublicKeys")
if ($sshKey) {
    if ($sshKey.name.Count -eq 1) { 
        Write-Output "`u{2705} Checked if the public SSH key resource exists - OK"
    }  else { 
        Write-Output `u{1F914}
        throw "More than one public SSH key resource was found in the VM resource group. Please make sure that your script creates only one public SSH key resource and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find public SSH key resouce. Please make sure that your script creates a public SSH key resouce and try again."
}

$sshKeyName = $sshKey.name.Replace("[parameters('sshPublicKeys_", "").Replace("_name')]", "")
if ($sshKeyName -eq "linuxboxsshkey") { 
    Write-Output "`u{2705} Checked the public ssh key name - OK"
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify the public ssh key name. Please make sure that your script creates a public ssh key called 'linuxboxsshkey' and try again."
}

$virtualMachine = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Compute/virtualMachines" )
if ($virtualMachine) {
    if ($virtualMachine.name.Count -eq 1) { 
        Write-Output "`u{2705} Checked if Virtual Machine exists - OK."
    }  else { 
        Write-Output `u{1F914}
        throw "More than one Virtual Machine resource was found in the VM resource group. Please make sure that your script creates only 1 VM and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find Virtual Machine in the task resource group. Please make sure that your script creates a virtual machine and try again."
}

if ($virtualMachine.identity.type -eq "SystemAssigned") { 
    Write-Output "`u{2705} Checked if VM has system-assigned identity enabled - OK."
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify that VM has system-assigned mannaged identity enabled. Please check if you are enabling the system-assigned mannaged identity on the VM and try again."
}

$nic = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Network/networkInterfaces")
if ($nic) {
    if ($nic.name.Count -eq 1) { 
        Write-Output "`u{2705} Checked if the Network Interface resource exists - OK"
    }  else { 
        Write-Output `u{1F914}
        throw "More than one Network Interface resource was found in the VM resource group. Please delete all un-used Network Interface resources and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find Network Interface resouce. Please re-deploy the VM and try again."
}

if ($nic.properties.ipConfigurations.Count -eq 1) { 
    if ($nic.properties.ipConfigurations.properties.publicIPAddress -and $nic.properties.ipConfigurations.properties.publicIPAddress.id) {  
        Write-Output "`u{2705} Checked if the Public IP assigned to the VM - OK"
    } else { 
        Write-Output `u{1F914}
        throw "Unable to verify Public IP configuratio for the VM. Please make sure that your script assignes the public IP address to the VM and try agian."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to verify IP configuration of the Network Interface. Please make sure that your script creates only 1 IP configuration of the VM network interface and try again."
}

if ($virtualMachine.properties.osProfile.linuxConfiguration.ssh.publicKeys.keyData -eq $sshKey.properties.publicKey) { 
    Write-Output "`u{2705} Checked if virtual machine uses the public ssh key 'linuxboxsshkey' - OK"
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify, that VM uses the public ssh key 'linuxboxsshkey'. Please make sure that in New-AzVm comandled, parameter '-SshKeyName' is set to the name of the public SSH key you created earlier, and that you are not setting the parameter '-GenerateSshKey'."
}

if ($virtualMachine.properties.storageProfile.imageReference.publisher -eq "canonical") { 
    Write-Output "`u{2705} Checked Virtual Machine OS image publisher - OK" 
} else { 
    Write-Output `u{1F914}
    throw "Virtual Machine uses OS image from unknown published. Please make sure that your script creates a VM from image with friendly name 'Ubuntu2204' and try again."
}
if ($virtualMachine.properties.storageProfile.imageReference.offer.Contains('ubuntu-server') -and $virtualMachine.properties.storageProfile.imageReference.sku.Contains('22_04')) { 
    Write-Output "`u{2705} Checked Virtual Machine OS image offer - OK"
} else { 
    Write-Output `u{1F914}
    throw "Virtual Machine uses wrong OS image. Please make sure that your script creates a VM from image with friendly name 'Ubuntu2204' and try again." 
}

if ($virtualMachine.properties.hardwareProfile.vmSize -eq "Standard_B1s") { 
    Write-Output "`u{2705} Checked Virtual Machine size - OK"
} else { 
    Write-Output `u{1F914}
    throw "Virtual Machine size is not set to B1s. Please make sure that your script creates a VM with size B1s and try again."
}

$extention = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Compute/virtualMachines/extensions" )
if ($extention) {
    if ($extention.name.Count -eq 1) {
        Write-Output "`u{2705} Checked if VM extention resource exists - OK."
    }  else { 
        Write-Output `u{1F914}
        throw "More than one VM extention resource was found in the task resource group. Please make sure that your script creates only 1 VM extention and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find VM extention resource in the task resource group. Please make sure that your script creates a VM extention and try again."
}

if ($extention.properties.type -eq "CustomScript") { 
    Write-Output "`u{2705} Checked the VM extention type - OK."
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify the extention type. Please make sure that you are using a VM extention with type 'CustomScript' and try again."
}

if ($extention.properties.settings.fileUris[0]) { 
    if ($extention.properties.settings.fileUris[0].Contains("https://raw.githubusercontent.com/")) { 
        Write-Output "`u{2705} Checked the VM extention script URI - OK."
    } else { 
        Write-Output `u{1F914}
        throw "Unable to verify the script URL in the extention settings. Please make sure that your custom script extention loads the app install script from the github and try again."
    }
 } else { 
    Write-Output `u{1F914}
    throw "Unable to verify the script URL in the extention settings. Please make sure that you are setting the script URI when deploying the extention."
}

$dcr = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Insights/dataCollectionRules")
if ($dcr) {
    if ($dcr.name.Count -eq 1) { 
        Write-Output "`u{2705} Checked if the data collection rule exists - OK"
    }  else { 
        Write-Output `u{1F914}
        throw "More than one Azure Monitor Data Collection rule was found in the VM resource group. Please delete all un-used data collection rules and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find Azure Monitor Data Collection Rule in the task resource group. Please make sure that you created a data collection rule for the VM and again."
}


# Check the log of Azure Monitor Agent on the VM to make sure that VM 
# loaded data collection rule and started sending the OS-level metrics. 
# To access the log, I am creating a symlink at a todoapp startup (see script: azure_task_13_vm_monitoring/app/start.sh)
$response = (Invoke-WebRequest -Uri "http://$($pip.properties.dnsSettings.fqdn):8080/static/files/azuremonitoragent/log/mdsd.info" -ErrorAction SilentlyContinue -SkipHttpErrorCheck) 
if ($response) { 
    Write-Output "`u{2705} Checked if the web application is running - OK"
    
    if ($response.StatusCode -eq 404) { 
        throw "Unable to verify that the new version of the todo app was deployed to the VM. Please make sure that you deployed the new version of the application to the server, check if Azure Monitor Extention was installed to the VM and running, and try to re-run validation script again."
    }

    if ($response.StatusCode -ne 200) { 
        throw "Unexpected error, unable to verify that the web app is configured properly. Please check the configuration of your web application and ensure, that the HTTP request to the following URL returnts HTTP status code 200 and try to re-run validation script again: http://$($pip.properties.dnsSettings.fqdn):8080/static/files/azuremonitoragent/log/mdsd.info"
    }

    $taskLogContent = [System.Text.Encoding]::UTF8.GetString($response.Content)

    if ($taskLogContent.Contains("Loaded Azure Monitor configuration dcr")) { 
        Write-Output "`u{2705} Checked if Azure Monitor Agend started sending metrics to Azure Monitor - OK"
    } else { 
        throw "Unable to verify that Azure Monitor Agent is sending metrics to Azure Monitor. Please check if guest OS metrics are already available (they should appear in 10-20 minutes after you installed Azure Monitor Agent and created data collection rule) and try to re-run the validation again."
    }

} else {
    throw "Unable to get a reponse from the web app. Please make sure that the VM and web application are running and try again."
}

Write-Output ""
Write-Output "`u{1F973} Congratulations! All tests passed!"
