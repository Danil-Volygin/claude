# Deep-Live-Cam: установка под Windows + NVIDIA (RTX 4060 Laptop 8 GB и похожие).
# Запуск:  powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# Что делает:
#   1. Проверяет git, ffmpeg, находит Python 3.11-3.13 (не тот, что первым в PATH).
#   2. Клонирует Deep-Live-Cam в папку рядом со скриптом.
#   3. Создаёт venv, ставит зависимости, onnxruntime-gpu с CUDA/cuDNN pip-пакетами.
#   4. Качает модели inswapper_128_fp16.onnx и gfpgan-1024.onnx.
#   5. Проверяет, что onnxruntime реально работает на видеокарте.
#   6. Кладёт start.bat для запуска.
#
# Флаг -WithTorch дополнительно ставит torch (2.8 ГБ). Без него всё работает, torch в Deep-Live-Cam опционален.
#
# CUDA Toolkit НЕ нужен. Файл сохранён в UTF-8 с BOM, иначе Windows PowerShell 5.1 ломает кириллицу.

param([switch]$WithTorch)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # без этого Invoke-WebRequest в PS 5.1 качает в 10 раз медленнее
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$App  = Join-Path $Root "Deep-Live-Cam"

function Fail($msg) { Write-Host "[!] $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "`n== $msg ==" -ForegroundColor Cyan }
function Run {
    # Запуск внешней команды с остановкой, если она упала.
    $exe = $args[0]; $rest = @($args | Select-Object -Skip 1)
    & $exe @rest
    if ($LASTEXITCODE -ne 0) { Fail "Команда упала (код $LASTEXITCODE): $exe $($rest -join ' ')" }
}
function Need($cmd, $hint) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Fail "Не найден '$cmd'. $hint" }
}

Step "Проверка окружения"
Need git    "Поставь Git: https://git-scm.com/download/win"
Need ffmpeg "Поставь ffmpeg (см. README.md, раздел 1) и перезапусти PowerShell."

# Ищем Python 3.11-3.13. Сначала прямые пути, потом py-launcher.
$Py = $null
foreach ($c in "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
               "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
               "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
               "C:\Program Files\Python312\python.exe",
               "C:\Program Files\Python311\python.exe",
               "C:\Python312\python.exe", "C:\Python311\python.exe") {
    if (Test-Path $c) { $Py = $c; break }
}
if (-not $Py -and (Get-Command py -ErrorAction SilentlyContinue)) {
    foreach ($v in "3.12","3.11","3.13") {
        try {
            $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
            $probe = & py "-$v" -c "import sys;print(sys.executable)" 2>$null
            $ErrorActionPreference = $old
            if ($LASTEXITCODE -eq 0 -and $probe) { $Py = ($probe | Select-Object -First 1).Trim(); break }
        } catch { $ErrorActionPreference = $old }
    }
}
if (-not $Py) { Fail "Не нашёл Python 3.11-3.13. Поставь 3.12 с https://www.python.org/downloads/windows/" }
Write-Host "Python: $Py ($(& $Py --version))"

$drive = $Root.Substring(0,1)
$free = [math]::Round((Get-PSDrive -Name $drive).Free / 1GB, 1)
Write-Host "Свободно на диске ${drive}: $free ГБ"
if ($free -lt 12) { Fail "Меньше 12 ГБ свободно. Освободи место и запусти снова." }

if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
} else {
    Write-Host "[!] nvidia-smi не найден. Обнови драйвер NVIDIA." -ForegroundColor Yellow
}

Step "Клонирование Deep-Live-Cam"
if (-not (Test-Path (Join-Path $App "run.py"))) {
    Run git clone --depth 1 https://github.com/hacksider/Deep-Live-Cam.git $App
} else {
    Write-Host "Уже склонировано, пропускаю."
}
Set-Location $App

Step "Виртуальное окружение"
$VPy = Join-Path $App "venv\Scripts\python.exe"
if (-not (Test-Path $VPy)) { Run $Py -m venv venv }
Run $VPy -m pip install --upgrade pip

Step "Зависимости (это долго, 5-15 минут)"
Run $VPy -m pip install -r requirements.txt

Step "onnxruntime-gpu + CUDA/cuDNN pip-пакеты (~1.2 ГБ)"
& $VPy -m pip uninstall -y onnxruntime
Run $VPy -m pip install "onnxruntime-gpu[cuda,cudnn]==1.26.0"

if ($WithTorch) {
    Step "PyTorch для CUDA 12.8 (2.8 ГБ, опционально)"
    Run $VPy -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128
}

Step "Модели"
New-Item -ItemType Directory -Force -Path "models" | Out-Null
$models = [ordered]@{
    "inswapper_128_fp16.onnx" = "https://huggingface.co/hacksider/deep-live-cam/resolve/main/inswapper_128_fp16.onnx"
    "gfpgan-1024.onnx"        = "https://huggingface.co/hacksider/deep-live-cam/resolve/main/gfpgan-1024.onnx"
}
foreach ($name in $models.Keys) {
    $dst = Join-Path "models" $name
    if ((Test-Path $dst) -and (Get-Item $dst).Length -gt 1MB) { Write-Host "$name уже есть"; continue }
    Write-Host "Качаю $name ..."
    Invoke-WebRequest -Uri $models[$name] -OutFile $dst -UseBasicParsing
}

Step "Проверка: onnxruntime реально работает на видеокарте"
$check = Join-Path $env:TEMP "dlc_cuda_check.py"
@'
import onnxruntime as ort
try:
    ort.preload_dlls()
except Exception as e:
    print("preload_dlls:", e)
s = ort.InferenceSession("models/inswapper_128_fp16.onnx", providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
p = s.get_providers()
print("onnxruntime", ort.__version__, p)
if p[0] != "CUDAExecutionProvider":
    raise SystemExit("FAIL: CUDA не поднялась, всё будет на процессоре")
print("OK: swap будет на видеокарте")
'@ | Set-Content -Path $check -Encoding ASCII
Run $VPy $check

Step "Чистка pip-кэша (вернёт 2-3 ГБ)"
& $VPy -m pip cache purge

Step "Лаунчер"
Copy-Item (Join-Path $Root "start.bat") (Join-Path $App "start.bat") -Force

Write-Host "`nГотово. Запуск: $App\start.bat" -ForegroundColor Green
Write-Host "Дальше по README.md: OBS -> Virtual Camera -> Discord."
