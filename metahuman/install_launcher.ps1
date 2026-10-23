& {
# Ставит Epic Games Launcher и открывает его на странице Unreal Engine.
# Сам движок ставится кнопкой в лаунчере: консольного установщика у Epic нет.
$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$free = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Host "Свободно на C: $free ГБ" -ForegroundColor Cyan
if ($free -lt 80) { Write-Host "[!] Нужно минимум 80 ГБ под движок и проект. Освободи место." -ForegroundColor Red; return }

function Find-Launcher {
    foreach ($root in "${env:ProgramFiles(x86)}\Epic Games", "$env:ProgramFiles\Epic Games") {
        if (Test-Path $root) {
            $f = Get-ChildItem $root -Recurse -Filter EpicGamesLauncher.exe -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { return $f.FullName }
        }
    }
    return $null
}
$exe = Find-Launcher

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
    $exe = Find-Launcher
}
if ($exe) {
    Write-Host "Лаунчер: $exe" -ForegroundColor Green
} elseif (Test-Path "Registry::HKEY_CLASSES_ROOT\com.epicgames.launcher") {
    Write-Host "Файл лаунчера не нашёл, но ссылки Epic зарегистрированы, открываю через них." -ForegroundColor Yellow
} else {
    Write-Host "[!] Лаунчер не установился. Скачай руками: https://store.epicgames.com/download" -ForegroundColor Red
    return
}

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
