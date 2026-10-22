& {
# Ставит Epic Games Launcher и открывает его на странице Unreal Engine.
# Сам движок ставится кнопкой в лаунчере: консольного установщика у Epic нет.
$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$free = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Host "Свободно на C: $free ГБ" -ForegroundColor Cyan
if ($free -lt 80) { Write-Host "[!] Нужно минимум 80 ГБ под движок и проект. Освободи место." -ForegroundColor Red; return }

$exe = @("${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe",
         "${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe",
         "$env:ProgramFiles\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe") |
       Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $exe) {
    Write-Host "== Качаю Epic Games Launcher ==" -ForegroundColor Cyan
    $msi = Join-Path $env:TEMP "EpicGamesLauncherInstaller.msi"
    try {
        Invoke-WebRequest "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi" -OutFile $msi -UseBasicParsing
    } catch {
        Write-Host "[!] Не скачалось: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    Включи VPN и запусти снова, или скачай руками: https://store.epicgames.com/download" -ForegroundColor Yellow
        return
    }
    Write-Host "== Ставлю (спросит права администратора, жми Да) ==" -ForegroundColor Cyan
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /passive /norestart" -Verb RunAs -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { Write-Host "[!] Установщик вернул код $($p.ExitCode)" -ForegroundColor Red; return }
    $exe = @("${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe",
             "${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe") |
           Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $exe) { Write-Host "[!] Лаунчер не нашёлся после установки" -ForegroundColor Red; return }
Write-Host "Лаунчер: $exe" -ForegroundColor Green

Write-Host "== Открываю лаунчер на вкладке Unreal Engine ==" -ForegroundColor Cyan
Start-Process "com.epicgames.launcher://ue/library"

Write-Host ""
Write-Host "Дальше руками в лаунчере:" -ForegroundColor Green
Write-Host " 1. Войди в аккаунт Epic."
Write-Host " 2. Unreal Engine -> Library -> + рядом с Engine Versions -> самая свежая версия (не ниже 5.6)."
Write-Host " 3. Install -> Options: оставь только Windows, сними Starter Content, Templates and Feature Packs,"
Write-Host "    Engine Source, Editor symbols for debugging."
Write-Host " 4. Install. Если загрузка висит на 0%, включи VPN, пауза и продолжить."
}
