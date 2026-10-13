@echo off
rem Double-click to install or update WowPad on your benilla folder (it asks which one).
rem It runs install.ps1 next to it; read that file to see every step.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
