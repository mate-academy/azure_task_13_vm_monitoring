# Сначала получаем VM
$vm = Get-AzVM -ResourceGroupName "mate-azure-task-13" -Name "matebox"

# Проверяем статус расширения Azure Monitor Agent (AMA)
Get-AzVMExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name | 
Where-Object {$_.Publisher -like "*Microsoft.Azure.Monitor*"} | 
Select-Object Name, ProvisioningState, TypeHandlerVersion