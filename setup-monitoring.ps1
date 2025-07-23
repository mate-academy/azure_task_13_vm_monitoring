# --- Змінні конфігурації ---
$resourceGroupName = "mate-azure-task-13" # Ваша існуюча група ресурсів
$location = "uksouth" # Регіон, де розгорнуті ваші ресурси (може бути іншим, перевірте свій ресурс)

# Змінні для Log Analytics Workspace
$logAnalyticsWorkspaceName = "LogAnalyticsWorkspaceTask17" # Ім'я вашої робочої області Log Analytics

# Змінні для Data Collection Rule (DCR)
$dcrName = "myVMosMetricsDCR" # Ім'я DCR
$dcrJsonPath = "./dcr.json" # Шлях до файлу dcr.json у поточній директорії
$vmName = "matebox" # Ім'я вашої віртуальної машини (якщо відрізняється від matebox)

# --- Перевірка входу в Azure ---
Write-Host "Перевірка підключення до Azure..."
try {
    # Спроба отримати поточний контекст облікового запису
    $null = Get-AzContext -ErrorAction Stop
    Write-Host "Успішно підключено до Azure."
} catch {
    Write-Error "Не вдалося підключитися до Azure. Будь ласка, виконайте 'Connect-AzAccount'."
    exit 1
}

# --- 1. Створення або перевірка існування робочої області Log Analytics ---
Write-Host "Створення або перевірка існування робочої області Log Analytics '$logAnalyticsWorkspaceName'..."
$logAnalyticsWorkspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $logAnalyticsWorkspaceName -ErrorAction SilentlyContinue

if (-not $logAnalyticsWorkspace) {
    Write-Host "Робоча область Log Analytics '$logAnalyticsWorkspaceName' не знайдена. Створення..."
    $logAnalyticsWorkspace = New-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $logAnalyticsWorkspaceName -Location $location
    Write-Host "Робоча область Log Analytics '$logAnalyticsWorkspaceName' успішно створена."
} else {
    Write-Host "Робоча область Log Analytics '$logAnalyticsWorkspaceName' вже існує. Використовуємо існуючу."
}

# --- 2. Створення Data Collection Rule (DCR) ---
Write-Host "Створення або перевірка існування Data Collection Rule '$dcrName'..."

# Переконайтеся, що файл dcr.json існує
if (-not (Test-Path $dcrJsonPath)) {
    Write-Error "Файл dcr.json не знайдено за шляхом '$dcrJsonPath'. Будь ласка, створіть його."
    exit 1
}

$dcr = Get-AzDataCollectionRule -ResourceGroupName $resourceGroupName -RuleName $dcrName -ErrorAction SilentlyContinue

if (-not $dcr) {
    Write-Host "Data Collection Rule '$dcrName' не знайдена. Створення..."
    # Читаємо вміст dcr.json та перетворюємо його на об'єкт PowerShell
    $dcrProperties = Get-Content $dcrJsonPath | Out-String | ConvertFrom-Json

    # Використовуємо New-AzResource для створення DCR
    $dcr = New-AzResource -ResourceGroupName $resourceGroupName -Name $dcrName `
                         -ResourceType "Microsoft.Insights/dataCollectionRules" `
                         -ApiVersion "2021-09-01-preview" `
                         -Location $location `
                         -Properties $dcrProperties.properties -Force -ErrorAction Stop
    Write-Host "Data Collection Rule '$dcrName' успішно створена."

    # !!! ДОДАНО !!! Отримуємо повний об'єкт DCR, щоб його Id був коректним
    $dcr = Get-AzDataCollectionRule -ResourceGroupName $resourceGroupName -RuleName $dcrName -ErrorAction Stop
} else {
    Write-Host "Data Collection Rule '$dcrName' вже існує. Використовуємо існуючу."
}

# --- 3. Прив'язка DCR до ВМ ---
Write-Host "Прив'язка Data Collection Rule '$dcrName' до віртуальної машини '$vmName'..."
$vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -ErrorAction SilentlyContinue

if (-not $vm) {
    Write-Error "Віртуальна машина '$vmName' не знайдена в групі ресурсів '$resourceGroupName'. Перевірте ім'я ВМ та групу ресурсів."
    exit 1
}

# Перевірка, чи вже існує асоціація DCR з цією VM
$associationName = "$($dcr.Name)-to-$($vm.Name)-association" # Унікальне ім'я для асоціації
try {
    $dcrAssociation = Get-AzDataCollectionRuleAssociation -RuleId $dcr.Id -TargetResourceId $vm.Id -ErrorAction SilentlyContinue
} catch {
    $dcrAssociation = $null
}

if (-not $dcrAssociation) {
    Write-Host "Асоціація DCR з ВМ не знайдена. Створення нової асоціації..."
    New-AzDataCollectionRuleAssociation -Name $associationName -RuleId $dcr.Id -TargetResourceId $vm.Id -ErrorAction Stop
    Write-Host "DCR '$dcrName' успішно прив'язана до ВМ '$vmName'."
} else {
    Write-Host "DCR '$dcrName' вже прив'язана до ВМ '$vmName'."
}

Write-Host "Налаштування моніторингу завершено. Зачекайте 10-20 хвилин, доки метрики почнуть надходити до Log Analytics."