@echo off
rem Запуск Deep-Live-Cam на видеокарте NVIDIA.
rem Файл копируется скриптом install.ps1 внутрь папки Deep-Live-Cam.
cd /d "%~dp0"
call venv\Scripts\activate.bat
python run.py --execution-provider cuda --execution-threads 4 --max-memory 6
pause
