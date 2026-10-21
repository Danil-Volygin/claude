@echo off
rem Deep-Live-Cam launcher (NVIDIA CUDA). Copied into the Deep-Live-Cam folder by install.ps1.
cd /d "%~dp0"
"venv\Scripts\python.exe" run.py --execution-provider cuda --execution-threads 4 --max-memory 6
pause
