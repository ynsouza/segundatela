@echo off
title Instalar Tela do Cliente - Padaria Silmar
set "DEST=C:\TelaCliente"
echo.
echo  ==============================================
echo    INSTALANDO A TELA DO CLIENTE
echo  ==============================================
echo.

echo  [1/4] Parando versao anterior (se houver)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'TelaCliente\.ps1|perfil-edge' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
timeout /t 2 /nobreak >nul

echo  [2/4] Copiando arquivos para %DEST% ...
if not exist "%DEST%" mkdir "%DEST%"
if not exist "%DEST%\divulgacao" mkdir "%DEST%\divulgacao"
if not exist "%DEST%\cardapio" mkdir "%DEST%\cardapio"
robocopy "%~dp0." "%DEST%" /E /XF config.json INSTALAR.bat LEIA-ME.txt /XD divulgacao cardapio /NFL /NDL /NJH /NJS /NP >nul
if not exist "%DEST%\config.json" copy /Y "%~dp0config.json" "%DEST%\config.json" >nul
rem Config antigo sem o link do QR: preenche com o link desta versao (o resto do config fica como esta)
powershell -NoProfile -Command "$n=[IO.File]::ReadAllText('%~dp0config.json'); $c=[IO.File]::ReadAllText('%DEST%\config.json'); $m=[regex]::Match($n,'\"qr_link\"\s*:\s*\"(.+?)\"'); if ($m.Success -and $c -match '\"qr_link\"\s*:\s*\"\s*\"') { $c=[regex]::Replace($c,'\"qr_link\"\s*:\s*\"\s*\"','\"qr_link\": \"'+$m.Groups[1].Value+'\"'); [IO.File]::WriteAllText('%DEST%\config.json',$c,(New-Object Text.UTF8Encoding $false)) }"
robocopy "%~dp0divulgacao" "%DEST%\divulgacao" /XC /XN /XO /NFL /NDL /NJH /NJS /NP >nul
if exist "%~dp0cardapio" robocopy "%~dp0cardapio" "%DEST%\cardapio" /XC /XN /XO /NFL /NDL /NJH /NJS /NP >nul
copy /Y "%~dp0LEIA-ME.txt" "%DEST%\LEIA-ME.txt" >nul

echo  [3/4] Configurando para abrir junto com o Windows...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup') + '\Tela do Cliente.lnk'); $s.TargetPath='wscript.exe'; $s.Arguments='C:\TelaCliente\iniciar.vbs'; $s.WorkingDirectory='C:\TelaCliente'; $s.Description='Tela do Cliente - Padaria Silmar'; $s.Save()"

echo  [4/4] Iniciando...
start "" wscript.exe "%DEST%\iniciar.vbs"

echo.
echo  Pronto! Em alguns segundos a tela do cliente vai acender.
echo  A partir de agora ela abre sozinha sempre que o computador ligar.
echo.
pause
