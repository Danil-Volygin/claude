# Удаляет Deep-Live-Cam (с моделями) и Camo. Сначала показывает список и спрашивает подтверждение.
# Не трогает: OBS (нужен для Discord), Unreal Engine, Python, ffmpeg, папку C:\AI\claude с гайдами.
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File C:\AI\claude\tools\remove_dlc_camo.ps1

$ErrorActionPreference = "SilentlyContinue"

function SizeGB($p) {
    if (-not (Test-Path -LiteralPath $p)) { return 0 }
    $i = Get-Item -LiteralPath $p -Force
    if ($i.PSIsContainer) { $s = (Get-ChildItem -LiteralPath $p -Recurse -Force -File | Measure-Object Length -Sum).Sum } else { $s = $i.Length }
    [math]::Round($s / 1GB, 2)
}

$paths = @(
    "C:\AI\claude\deep-live-cam\Deep-Live-Cam",
    "$env:USERPROFILE\.insightface",
    "$env:USERPROFILE\Desktop\Deep-Live-Cam.lnk",
    "$env:USERPROFILE\Desktop\dlc_before.jpg",
    "$env:USERPROFILE\Desktop\dlc_after.jpg",
    "$env:USERPROFILE\Desktop\sysreport.txt",
    "$env:TEMP\dlc-setup",
    "$env:TEMP\dlc_cuda_check.py"
) | Where-Object { Test-Path -LiteralPath $_ }

$uninstallKeys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                 "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                 "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
$camo = Get-ItemProperty $uninstallKeys | Where-Object { $_.DisplayName -match '^Camo' -or $_.Publisher -match 'Reincubate' }

Write-Host "== Будет удалено ==" -ForegroundColor Cyan
$total = 0
foreach ($p in $paths) { $g = SizeGB $p; $total += $g; Write-Host ("  {0,6} ГБ  {1}" -f $g, $p) }
foreach ($c in $camo) { Write-Host ("  программа  {0} {1}" -f $c.DisplayName, $c.DisplayVersion) }
if (-not $paths -and -not $camo) { Write-Host "Нечего удалять, всё уже чисто." -ForegroundColor Green; return }
Write-Host ("Освободится примерно {0} ГБ плюс место Camo" -f [math]::Round($total,1))
Write-Host "`nНе трогаю: OBS, Unreal Engine, Python, ffmpeg, гайды в C:\AI\claude." -ForegroundColor DarkGray

$a = Read-Host "`nУдалить? Введи y и нажми Enter"
if ($a -ne "y") { Write-Host "Отменено, ничего не удалено."; return }

Write-Host "`n== Закрываю процессы ==" -ForegroundColor Cyan
Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "C:\AI\claude\deep-live-cam\*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-Process | Where-Object { $_.ProcessName -match '^Camo' } | Stop-Process -Force
Start-Sleep 2

Write-Host "== Удаляю файлы Deep-Live-Cam ==" -ForegroundColor Cyan
foreach ($p in $paths) {
    Remove-Item -LiteralPath $p -Recurse -Force
    if (Test-Path -LiteralPath $p) { Write-Host "  [!] не удалилось: $p" -ForegroundColor Yellow } else { Write-Host "  удалено: $p" }
}

foreach ($c in $camo) {
    Write-Host "== Удаляю $($c.DisplayName) (может спросить права администратора) ==" -ForegroundColor Cyan
    $cmd = if ($c.QuietUninstallString) { $c.QuietUninstallString } else { $c.UninstallString }
    if (-not $cmd) { Write-Host "  [!] Нет команды удаления. Удали Camo руками: Параметры -> Приложения." -ForegroundColor Yellow; continue }
    if ($cmd -match 'msiexec') {
        $guid = [regex]::Match($cmd, '\{[0-9A-Fa-f\-]+\}').Value
        Start-Process msiexec.exe -ArgumentList "/x $guid /passive /norestart" -Verb RunAs -Wait
    } else {
        Start-Process cmd.exe -ArgumentList "/c `"$cmd`"" -Verb RunAs -Wait
    }
}

$left = Get-ItemProperty $uninstallKeys | Where-Object { $_.DisplayName -match '^Camo' -or $_.Publisher -match 'Reincubate' }
if ($left) { Write-Host "[!] Camo всё ещё в списке программ. Удали руками: Параметры -> Приложения -> Camo." -ForegroundColor Yellow }

Write-Host ("`nГотово. Свободно на C: {0} ГБ" -f [math]::Round((Get-PSDrive C).Free/1GB,1)) -ForegroundColor Green
