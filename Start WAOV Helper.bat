@echo off
title WAOV installer helper
rem Keeps the backdoor Installer Control tile connected. Leave this window open while you use the tile.
cd /d "%~dp0"
python -I helper.py
pause
