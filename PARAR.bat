@echo off
title Parar Tela do Cliente
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'TelaCliente\.ps1|perfil-edge' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
echo Tela do Cliente parada. Para ligar de novo, de dois cliques em iniciar.vbs
timeout /t 4 >nul
