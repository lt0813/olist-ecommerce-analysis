@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path '%~dp0' 'Setup_Olist_Model.ps1'; $s = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8); & ([ScriptBlock]::Create($s))"
pause
