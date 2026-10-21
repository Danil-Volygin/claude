# Deep-Live-Cam: установка под Windows + NVIDIA (RTX 4060 Laptop 8 GB и похожие).
# Запуск: ПКМ по файлу -> "Выполнить с помощью PowerShell",
# или в PowerShell:  powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# Что делает:
#   1. Проверяет git, python, ffmpeg.
#   2. Клонирует Deep-Live-Cam в папку рядом со скриптом.
#   3. Создаёт venv, ставит зависимости, torch для CUDA 12.8, onnxruntime-gpu.
#   4. Качает модели inswapper_128_fp16.onnx и gfpgan-1024.onnx.
#   5. Кладёт start.bat для запуска.
#
# Нужно заранее: ~12 ГБ свободного места, Python 3.11-3.13 с python.org, git, ffmpeg.
# CUDA Toolkit НЕ нужен: CUDA/cuDNN DLL приезжают pip-пакетами внутрь venv.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$App  = Join-Path $Root "Deep-Live-Cam"

function Need($cmd, $hint) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "[!] Не найден '$cmd'. $hint" -ForegroundColor Red
        exit 1
    }
}

Write-Host "== Проверка окружения ==" -ForegroundColor Cyan
Need git    "Поставь Git: https://git-scm.com/download/win"
Need ffmpeg "Поставь ffmpeg: в PowerShell выполни  iex (irm ffmpeg.tc.ht)  и перезапусти терминал."

# Ищем нормальный Python 3.11-3.13 через py-launcher, а не тот, что первым попался в PATH
# (у тебя в PATH торчит python 3.9 из venv PyCharm, он не подходит).
$Py = $null
foreach ($v in "3.12","3.11","3.13") {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $probe = & py "-$v" -c "import sys;print(sys.executable)" 2>$null
        if ($LASTEXITCODE -eq 0 -and $probe) { $Py = $probe.Trim(); break }
    }
}
if (-not $Py) {
    foreach ($c in "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
                   "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
                   "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
                   "C:\Python312\python.exe","C:\Python311\python.exe") {
        if (Test-Path $c) { $Py = $c; break }
    }
}
if (-not $Py) {
    Write-Host "[!] Не нашёл Python 3.11-3.13. Поставь 3.12 с https://www.python.org/downloads/windows/" -ForegroundColor Red
    Write-Host "    При установке отметь 'Add python.exe to PATH' и 'py launcher'." -ForegroundColor Red
    exit 1
}
Write-Host "Python: $Py ($(& $Py --version))"

$free = [math]::Round((Get-PSDrive -Name ($Root.Substring(0,1))).Free / 1GB, 1)
Write-Host "Свободно на диске $($Root.Substring(0,1)): $free ГБ"
if ($free -lt 12) {
    Write-Host "[!] Меньше 12 ГБ свободно. Освободи место и запусти снова." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    Write-Host "[!] nvidia-smi не найден. Обнови драйвер NVIDIA." -ForegroundColor Yellow
} else {
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
}

Write-Host "`n== Клонирование Deep-Live-Cam ==" -ForegroundColor Cyan
if (-not (Test-Path $App)) {
    git clone --depth 1 https://github.com/hacksider/Deep-Live-Cam.git $App
} else {
    Write-Host "Папка уже есть, пропускаю clone."
}
Set-Location $App

Write-Host "`n== Виртуальное окружение ==" -ForegroundColor Cyan
if (-not (Test-Path "venv")) { & $Py -m venv venv }
& ".\venv\Scripts\Activate.ps1"
python -m pip install --upgrade pip

Write-Host "`n== Зависимости (это долго, 5-15 минут) ==" -ForegroundColor Cyan
pip install -r requirements.txt

Write-Host "`n== PyTorch для CUDA 12.8 + onnxruntime-gpu ==" -ForegroundColor Cyan
pip install -U torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
pip uninstall -y onnxruntime onnxruntime-gpu
pip install onnxruntime-gpu==1.26.0
# CUDA runtime и cuDNN 9 как pip-пакеты, чтобы не ставить CUDA Toolkit целиком
pip install nvidia-cuda-runtime-cu12 nvidia-cudnn-cu12 nvidia-cublas-cu12 nvidia-cufft-cu12

Write-Host "`n== Модели ==" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path "models" | Out-Null
$models = @{
    "inswapper_128_fp16.onnx" = "https://huggingface.co/hacksider/deep-live-cam/resolve/main/inswapper_128_fp16.onnx"
    "gfpgan-1024.onnx"        = "https://huggingface.co/hacksider/deep-live-cam/resolve/main/gfpgan-1024.onnx"
}
foreach ($name in $models.Keys) {
    $dst = Join-Path "models" $name
    if (Test-Path $dst) { Write-Host "$name уже есть"; continue }
    Write-Host "Качаю $name ..."
    Invoke-WebRequest -Uri $models[$name] -OutFile $dst
}

Write-Host "`n== Проверка: onnxruntime реально поднимает CUDA ==" -ForegroundColor Cyan
python -c @"
import torch, onnxruntime as ort
print('torch', torch.__version__, 'cuda', torch.cuda.is_available())
ort.preload_dlls()
s = ort.InferenceSession('models/inswapper_128_fp16.onnx', providers=['CUDAExecutionProvider','CPUExecutionProvider'])
p = s.get_providers()
print('onnxruntime', ort.__version__, p)
assert p[0] == 'CUDAExecutionProvider', 'CUDA provider не поднялся, сессия на CPU'
print('OK: swap будет на видеокарте')
"@

Write-Host "`n== Чистка pip-кэша (вернёт 2-3 ГБ на диске) ==" -ForegroundColor Cyan
pip cache purge

Write-Host "`n== Лаунчер ==" -ForegroundColor Cyan
Copy-Item (Join-Path $Root "start.bat") (Join-Path $App "start.bat") -Force

Write-Host "`nГотово. Запуск: $App\start.bat" -ForegroundColor Green
Write-Host "Дальше по README.md: OBS -> Virtual Camera -> Discord."
