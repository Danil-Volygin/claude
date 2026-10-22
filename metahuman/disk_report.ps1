# Показывает, чем занят диск C, чтобы освободить место под Unreal Engine.
# Ничего не удаляет.
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File .\disk_report.ps1

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

function SizeGB($path) {
    $sum = (Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    [math]::Round($sum / 1GB, 1)
}

$drive = Get-PSDrive C
Write-Host ("Диск C: свободно {0} ГБ из {1} ГБ" -f [math]::Round($drive.Free/1GB,1), [math]::Round(($drive.Free+$drive.Used)/1GB,1)) -ForegroundColor Cyan

Write-Host "`n== Самые большие папки в профиле $env:USERPROFILE ==" -ForegroundColor Cyan
Write-Host "(считается несколько минут)"
Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Force |
    ForEach-Object { [pscustomobject]@{ GB = SizeGB $_.FullName; Path = $_.FullName } } |
    Sort-Object GB -Descending | Select-Object -First 12 | Format-Table -AutoSize

Write-Host "== Самые большие папки внутри AppData\Local ==" -ForegroundColor Cyan
Get-ChildItem -LiteralPath "$env:LOCALAPPDATA" -Directory -Force |
    ForEach-Object { [pscustomobject]@{ GB = SizeGB $_.FullName; Path = $_.FullName } } |
    Sort-Object GB -Descending | Select-Object -First 10 | Format-Table -AutoSize

Write-Host "== Известные места, которые обычно можно почистить ==" -ForegroundColor Cyan
$known = [ordered]@{
    "Временные файлы пользователя"         = $env:TEMP
    "Временные файлы Windows"              = "C:\Windows\Temp"
    "Кэш обновлений Windows"               = "C:\Windows\SoftwareDistribution\Download"
    "Загрузки"                             = "$env:USERPROFILE\Downloads"
    "Кэш pip"                              = "$env:LOCALAPPDATA\pip\Cache"
    "Кэш и логи JetBrains"                 = "$env:LOCALAPPDATA\JetBrains"
    "Кэш NVIDIA"                           = "$env:LOCALAPPDATA\NVIDIA"
    "Установщики NVIDIA"                   = "C:\ProgramData\NVIDIA Corporation\Downloader"
    "Кэш Hugging Face"                     = "$env:USERPROFILE\.cache\huggingface"
    "Кэш Telegram"                         = "$env:APPDATA\Telegram Desktop\tdata\user_data"
    "Steam: игры"                          = "C:\Program Files (x86)\Steam\steamapps\common"
    "Временная папка установки Deep-Live-Cam" = "$env:TEMP\dlc-setup"
}
$rows = foreach ($k in $known.Keys) {
    $p = $known[$k]
    if (Test-Path -LiteralPath $p) { [pscustomobject]@{ GB = SizeGB $p; What = $k; Path = $p } }
}
$rows | Sort-Object GB -Descending | Format-Table -AutoSize

Write-Host "== Самые большие файлы в профиле (больше 1 ГБ) ==" -ForegroundColor Cyan
Get-ChildItem -LiteralPath $env:USERPROFILE -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object Length -gt 1GB | Sort-Object Length -Descending | Select-Object -First 15 |
    Select-Object @{n='GB';e={[math]::Round($_.Length/1GB,1)}}, FullName | Format-Table -AutoSize

Write-Host "Скрипт ничего не удалял. Скинь вывод, и я скажу, что из этого безопасно чистить." -ForegroundColor Green
