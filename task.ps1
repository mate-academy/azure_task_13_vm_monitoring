# === CONFIG ===
$Rg = "mate-azure-task-13"
$VmName = "matebox"
# ===============

# Увімкнути system-assigned identity
$vm = Get-AzVM -ResourceGroupName $Rg -Name $VmName
if (-not $vm.Identity) { $vm.Identity = @{} }
$vm.Identity.Type = 'SystemAssigned'
Update-AzVM -ResourceGroupName $Rg -VM $vm | Out-Null

# Встановити Azure Monitor Agent
$extName = "AzureMonitorLinuxAgent"
$existing = Get-AzVMExtension -ResourceGroupName $Rg -VMName $VmName -Name $extName -ErrorAction SilentlyContinue
if (-not $existing) {
    Set-AzVMExtension `
      -ResourceGroupName $Rg `
      -VMName $VmName `
      -Name $extName `
      -Publisher "Microsoft.Azure.Monitor" `
      -ExtensionType "AzureMonitorLinuxAgent" `
      -TypeHandlerVersion "1.0" `
      -EnableAutomaticUpgrade $true `
      -Settings @{} | Out-Null
}

Write-Host "✅ System-assigned identity enabled and Azure Monitor Agent installed on VM: $VmName"