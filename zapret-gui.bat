@echo off
cd /d "%~dp0"
title ZAPRET GUI
powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0zapret-gui.ps1"
