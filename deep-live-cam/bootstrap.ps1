& {
# Полная установка Deep-Live-Cam без winget: Python 3.12, ffmpeg, OBS, репа, зависимости, модели.
$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dl = Join-Path $env:TEMP "dlc-setup"; New-Item -ItemType Directory -Force -Path $dl | Out-Null
New-Item -ItemType Directory -Force -Path C:\AI | Out-Null

# 1. Python 3.12 (в профиль пользователя, админ не нужен, системный PATH не трогаем)
$py = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
if (-not (Test-Path $py)) {
    Write-Host "== Python 3.12: качаю и ставлю ==" -ForegroundColor Cyan
    Invoke-WebRequest "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe" -OutFile "$dl\python.exe" -UseBasicParsing
    Start-Process "$dl\python.exe" -ArgumentList "/quiet InstallAllUsers=0 PrependPath=0 Include_launcher=1 InstallLauncherAllUsers=0 Include_test=0" -Wait
    if (-not (Test-Path $py)) { Write-Host "[!] Python не встал. Поставь руками: https://www.python.org/downloads/windows/" -ForegroundColor Red; return }
}
Write-Host "Python OK: $py" -ForegroundColor Green

# 2. ffmpeg в C:\AI\ffmpeg + в PATH пользователя
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    $bin = Get-ChildItem C:\AI\ffmpeg -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $bin) {
        Write-Host "== ffmpeg: качаю (~100 МБ) ==" -ForegroundColor Cyan
        Invoke-WebRequest "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -OutFile "$dl\ffmpeg.zip" -UseBasicParsing
        Expand-Archive "$dl\ffmpeg.zip" -DestinationPath C:\AI\ffmpeg -Force
        $bin = Get-ChildItem C:\AI\ffmpeg -Recurse -Filter ffmpeg.exe | Select-Object -First 1
    }
    $binDir = $bin.DirectoryName
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$binDir*") { [Environment]::SetEnvironmentVariable("Path", "$userPath;$binDir", "User") }
    $env:Path += ";$binDir"
}
Write-Host "ffmpeg OK" -ForegroundColor Green

# 3. OBS Studio (спросит права администратора, жми Да)
if (-not (Test-Path "C:\Program Files\obs-studio\bin\64bit\obs64.exe")) {
    try {
        Write-Host "== OBS Studio: качаю и ставлю ==" -ForegroundColor Cyan
        $rel = Invoke-RestMethod "https://api.github.com/repos/obsproject/obs-studio/releases/latest"
        $a = $rel.assets | Where-Object { $_.name -like "*.exe" -and $_.name -match "Installer" -and $_.name -match "x64" } | Select-Object -First 1
        Invoke-WebRequest $a.browser_download_url -OutFile "$dl\obs.exe" -UseBasicParsing
        Start-Process "$dl\obs.exe" -ArgumentList "/S" -Wait
        Write-Host "OBS OK" -ForegroundColor Green
    } catch {
        Write-Host "[!] OBS не встал сам, поставь потом руками: https://obsproject.com/download" -ForegroundColor Yellow
    }
} else { Write-Host "OBS OK" -ForegroundColor Green }

# 4. Репа с установщиком
if (-not (Test-Path C:\AI\claude\.git)) {
    git clone --branch claude/cool-fermi-gxf6rv https://github.com/Danil-Volygin/claude.git C:\AI\claude
} else {
    git -C C:\AI\claude pull
}
if (-not (Test-Path C:\AI\claude\deep-live-cam\install.ps1)) { Write-Host "[!] Репа не скачалась" -ForegroundColor Red; return }

# 5. Deep-Live-Cam: зависимости, модели, проверка CUDA
powershell -NoProfile -ExecutionPolicy Bypass -File C:\AI\claude\deep-live-cam\install.ps1
}
