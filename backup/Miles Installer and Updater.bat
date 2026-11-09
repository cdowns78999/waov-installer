@echo off
rem Backup launcher for We Are One Voice. Use it only if an antivirus blocks Miles Installer and Updater.exe.
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0..\launcher\Miles Installer and Updater.ps1"
