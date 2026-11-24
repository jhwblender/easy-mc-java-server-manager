@echo off
rem Asks a running manager to save, stop the server and exit (within ~1 second).
powershell -NoProfile -ExecutionPolicy Bypass -Command ". '%~dp0config.ps1'; $d = [Environment]::ExpandEnvironmentVariables($ServerDir); New-Item -ItemType File -Force (Join-Path $d 'manager-stop') | Out-Null; Write-Host 'Stop requested.'"
