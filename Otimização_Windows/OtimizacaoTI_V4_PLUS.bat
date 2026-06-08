@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title OTIMIZACAO TI V4 PLUS
color 0A
mode con: cols=120 lines=38

REM ============================================================
REM OTIMIZACAO TI - V4 PLUS
REM Limpeza | Otimizacao | Rede | Impressora | IA Windows | Inicializacao
REM Mantem as funcoes da V3 e adiciona melhorias operacionais.
REM ============================================================

set "SCRIPT_VERSION=4.1.0-plus"
set "PROJECT_DIR=%~dp0"
set "BASE_DIR=%ProgramData%\OtimizacaoTI"
set "LOG_DIR=%PROJECT_DIR%Log Tecnico"
set "MODULE_DIR=%~dp0modules"
set "AI_MODULE=%MODULE_DIR%\OtimizacaoTI_AI_Local.ps1"
set "LOCK_FILE=%BASE_DIR%\otimizacao_ti.lock"
set "LOCK_MAX_HOURS=12"
set "TOOLS_DIR=%~dp0tools\portable"
set "TOOL_CDI=%TOOLS_DIR%\CrystalDiskInfo\CrystalDiskInfoPortable.exe"
set "TOOL_TREE=%TOOLS_DIR%\TreeSizeFree\TreeSizeFree.exe"
set "TOOL_DISM64=%TOOLS_DIR%\DismPP\Dism++x64.exe"
set "TOOL_DISM86=%TOOLS_DIR%\DismPP\Dism++x86.exe"
set "TOOL_DISM_ARM64=%TOOLS_DIR%\DismPP\Dism++ARM64.exe"
set "TOOL_REVO=%TOOLS_DIR%\Revo Uninstaller Pro 5.4.7\Revo Uninstaller Pro.exe"
set "INVENTARIO_DIR=%~dp0tools\inventario"
set "INVENTARIO_PS1=%INVENTARIO_DIR%\Inventario-Corporativo-N3-LIVE-V4.ps1"
set "INVENTARIO_LOG_DIR=%PROJECT_DIR%Inventario Log"
set "LOCKS_DIR=%BASE_DIR%\Locks"
set "DISM_LOCK_DIR=%LOCKS_DIR%\dism.lock"
set "EXEC_MODE=COMPLETO"
set "WARNINGS=0"
set "ERRORS=0"
set "REBOOT_RECOMMENDED=0"
set "WORKER_TASK="
set "HELD_TASK_LOCK_NAME="
set "ACTIVE_TASK_LOCK_NAME="
set "ACTIVE_TASK_LOCK_PATH="

if /I "%~1"=="--task" (
    set "WORKER_TASK=%~2"
)
if /I "%~3"=="--heldlock" (
    set "HELD_TASK_LOCK_NAME=%~4"
)

net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo [OTIMIZACAO TI] Solicitando permissao de administrador...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath '%ComSpec%' -ArgumentList '/c','\"\"%~f0\"\" %*' -WorkingDirectory '%~dp0' -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }"
    if errorlevel 1 (
        echo.
        echo [ERRO] Nao foi possivel elevar para Administrador.
        echo Verifique se voce clicou em 'Sim' no UAC e tente novamente.
        pause
        exit /b 1
    )
    exit /b 0
)

if not exist "%BASE_DIR%" mkdir "%BASE_DIR%" >nul 2>&1
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
if not exist "%INVENTARIO_LOG_DIR%" mkdir "%INVENTARIO_LOG_DIR%" >nul 2>&1
if not exist "%LOCKS_DIR%" mkdir "%LOCKS_DIR%" >nul 2>&1
if not defined WORKER_TASK (
    call :handle_lock
    if errorlevel 1 exit /b 1
    call :write_lock
)

for /f %%I in ('powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%I"
set "LOG=%LOG_DIR%\OtimizacaoTI_%STAMP%.log"

call :log "============================================================"
call :log "OTIMIZACAO TI V4 PLUS iniciado"
call :log "Versao: %SCRIPT_VERSION%"
call :log "Computador: %COMPUTERNAME%"
call :log "Usuario: %USERNAME%"
call :log "Modo inicial: %EXEC_MODE%"
call :log "Log: %LOG%"
call :log "============================================================"
call :diagnostico_inicial_silencioso

if defined WORKER_TASK goto :worker_dispatch

goto :menu

:worker_dispatch
if /I "%WORKER_TASK%"=="limpeza" goto :limpeza
if /I "%WORKER_TASK%"=="otimizacao" goto :otimizacao
if /I "%WORKER_TASK%"=="rede" goto :rede
if /I "%WORKER_TASK%"=="impressora" goto :impressora
if /I "%WORKER_TASK%"=="diagnostico" goto :diagnostico
if /I "%WORKER_TASK%"=="tudo_rapido" goto :tudo_rapido
if /I "%WORKER_TASK%"=="tudo_completo" goto :tudo_completo
if /I "%WORKER_TASK%"=="inventario_live" goto :inventario_live
if /I "%WORKER_TASK%"=="otimizar_inicializacao" goto :otimizar_inicializacao
call :error "Worker task invalida: %WORKER_TASK%"
goto :worker_end

:handle_lock
if not exist "%LOCK_FILE%" exit /b 0
set "LOCK_PID="
set "LOCK_TS="
for /f "usebackq tokens=1,* delims==" %%A in ("%LOCK_FILE%") do (
    if /I "%%A"=="PID" set "LOCK_PID=%%B"
    if /I "%%A"=="TS" set "LOCK_TS=%%B"
)
if not defined LOCK_PID goto :lock_stale

set "LOCK_ALIVE=0"
for /f %%I in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p='%LOCK_PID%'; if($p -match '^\d+$' -and (Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue)){ '1' } else { '0' }"') do set "LOCK_ALIVE=%%I"

set "LOCK_EXPIRED=1"
if defined LOCK_TS (
    for /f %%I in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $ts=[datetime]::Parse('%LOCK_TS%'); if(((Get-Date)-$ts).TotalHours -lt %LOCK_MAX_HOURS%){ '0' } else { '1' } } catch { '1' }"') do set "LOCK_EXPIRED=%%I"
)

if "%LOCK_ALIVE%"=="1" if "%LOCK_EXPIRED%"=="0" (
    echo.
    echo [ATENCAO] Existe uma execucao ativa detectada.
    echo Arquivo de lock: %LOCK_FILE%
    set /p FORCELOCK=Deseja forcar remocao do lock e continuar? [S/N]: 
    if /I not "%FORCELOCK%"=="S" exit /b 1
    del /f /q "%LOCK_FILE%" >nul 2>&1
    exit /b 0
)

:lock_stale
echo.
echo [INFO] Lock antigo/corrompido detectado. Removendo automaticamente...
del /f /q "%LOCK_FILE%" >nul 2>&1
exit /b 0

:write_lock
set "CURRENT_PID="
for /f %%I in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$self=Get-CimInstance Win32_Process -Filter ('ProcessId=' + $PID); $pp=$self.ParentProcessId; if(-not $pp){ $pp=$PID }; [string]$pp"') do set "CURRENT_PID=%%I"
if not defined CURRENT_PID set "CURRENT_PID=0"
for /f %%I in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Date -Format s"') do set "CURRENT_TS=%%I"
(
    echo PID=%CURRENT_PID%
    echo TS=%CURRENT_TS%
    echo USER=%USERNAME%@%COMPUTERNAME%
)> "%LOCK_FILE%"
exit /b 0

:banner
cls
echo.
echo ========================================================================================================================
echo                                             OTIMIZACAO TI V4 PLUS
echo                   LIMPEZA ^| DESEMPENHO MAXIMO ^| REDE ^| IMPRESSORA ^| WINDOWS AI ^| INICIALIZACAO
echo ========================================================================================================================
echo.
echo Modo atual: %EXEC_MODE%
echo Log tecnico: %LOG%
echo.
exit /b

:menu
call :banner
echo Escolha uma opcao:
echo.
echo [1] LIMPEZA PROFUNDA DO WINDOWS
echo [2] OTIMIZACAO DE DESEMPENHO MAXIMO
echo [3] RESOLVER PROBLEMA DE REDE
echo [4] RESOLVER PROBLEMA DE IMPRESSORA
echo [5] REMOVER RECURSOS DE IA DO WINDOWS
echo [6] OTIMIZAR INICIALIZACAO
echo [7] DIAGNOSTICO COMPLETO DO SISTEMA
echo [8] EXECUTAR MANUTENCAO RAPIDA COMPLETA
echo [9] EXECUTAR MANUTENCAO COMPLETA AVANCADA
echo [I] INVENTARIO LIVE
echo [T] FERRAMENTAS PORTATEIS ^(CrystalDiskInfo / TreeSize / Dism++^)
echo [U] SESSOES DE USUARIO ^(logoff remoto controlado^)
echo [M] ALTERAR MODO DE EXECUCAO
echo [0] SAIR
echo.
set /p OP=Digite a opcao: 

if /I "%OP%"=="1" goto :limpeza
if /I "%OP%"=="2" goto :otimizacao
if /I "%OP%"=="3" goto :rede
if /I "%OP%"=="4" goto :impressora
if /I "%OP%"=="5" goto :ia_menu
if /I "%OP%"=="6" goto :otimizar_inicializacao
if /I "%OP%"=="7" goto :diagnostico
if /I "%OP%"=="8" goto :tudo_rapido
if /I "%OP%"=="9" goto :tudo_completo
if /I "%OP%"=="I" goto :inventario_live
if /I "%OP%"=="T" goto :tools_menu
if /I "%OP%"=="U" goto :users_menu
if /I "%OP%"=="M" goto :modo
if /I "%OP%"=="0" goto :fim

echo.
echo Opcao invalida.
timeout /t 2 >nul
goto :menu

:start_task
call :task_lock_acquire "task_%~1"
if errorlevel 1 (
    call :warn "A tarefa '%~1' ja esta em execucao. Solicitacao ignorada."
    exit /b 1
)
call :log "Executando tarefa na janela atual: %~1"
set "WORKER_TASK=%~1"
set "HELD_TASK_LOCK_NAME=task_%~1"
goto :worker_dispatch
exit /b 0

:task_lock_acquire
set "ACTIVE_TASK_LOCK_NAME=%~1"
set "ACTIVE_TASK_LOCK_PATH=%LOCKS_DIR%\%ACTIVE_TASK_LOCK_NAME%.lock"
if exist "%ACTIVE_TASK_LOCK_PATH%" (
    set "LOCK_OWNER_PID="
    set "LOCK_OWNER_TS="
    if exist "%ACTIVE_TASK_LOCK_PATH%\owner.txt" (
        for /f "usebackq tokens=1,* delims==" %%A in ("%ACTIVE_TASK_LOCK_PATH%\owner.txt") do (
            if /I "%%A"=="PID" set "LOCK_OWNER_PID=%%B"
            if /I "%%A"=="TS" set "LOCK_OWNER_TS=%%B"
        )
    )
    set "TASK_LOCK_STALE=0"
    if defined LOCK_OWNER_PID (
        set "TASK_LOCK_ALIVE=0"
        for /f %%I in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p='%LOCK_OWNER_PID%'; if($p -match '^\d+$' -and (Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue)){ '1' } else { '0' }"') do set "TASK_LOCK_ALIVE=%%I"
        if not "%TASK_LOCK_ALIVE%"=="1" set "TASK_LOCK_STALE=1"
    ) else (
        set "TASK_LOCK_STALE=1"
    )
    if defined LOCK_OWNER_TS (
        set "TASK_LOCK_EXPIRED=1"
        for /f %%I in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $ts=[datetime]::Parse('%LOCK_OWNER_TS%'); if(((Get-Date)-$ts).TotalHours -lt 8){ '0' } else { '1' } } catch { '1' }"') do set "TASK_LOCK_EXPIRED=%%I"
        if "%TASK_LOCK_EXPIRED%"=="1" set "TASK_LOCK_STALE=1"
    )
    if "%TASK_LOCK_STALE%"=="1" (
        call :warn "Lock orfao detectado para %ACTIVE_TASK_LOCK_NAME%. Removendo automaticamente."
        rmdir /s /q "%ACTIVE_TASK_LOCK_PATH%" >nul 2>&1
    )
)
mkdir "%ACTIVE_TASK_LOCK_PATH%" >nul 2>&1
if errorlevel 1 exit /b 1
for /f %%I in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$self=Get-CimInstance Win32_Process -Filter ('ProcessId=' + $PID); $pp=$self.ParentProcessId; if(-not $pp){ $pp=$PID }; [string]$pp"') do set "TASK_OWNER_PID=%%I"
if not defined TASK_OWNER_PID set "TASK_OWNER_PID=0"
for /f %%I in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Date -Format s"') do set "TASK_OWNER_TS=%%I"
(
    echo PID=%TASK_OWNER_PID%
    echo TS=%TASK_OWNER_TS%
    echo TASK=%ACTIVE_TASK_LOCK_NAME%
)> "%ACTIVE_TASK_LOCK_PATH%\owner.txt"
exit /b 0

:task_lock_release
set "REL_LOCK_NAME=%~1"
if "%REL_LOCK_NAME%"=="" exit /b 0
set "REL_LOCK_PATH=%LOCKS_DIR%\%REL_LOCK_NAME%.lock"
if exist "%REL_LOCK_PATH%" rmdir "%REL_LOCK_PATH%" >nul 2>&1
exit /b 0

:modo
call :banner
echo Selecione o modo de execucao:
echo.
echo [1] COMPLETO  - executa todas as rotinas normais.
echo [2] SEGURO    - evita acoes destrutivas sem confirmacao forte.
echo [3] REMOTO    - evita derrubar conexao remota/VPN/RDP.
echo [0] Voltar
echo.
set /p MODO=Digite a opcao: 
if "%MODO%"=="1" set "EXEC_MODE=COMPLETO"& call :log "Modo alterado para COMPLETO"& goto :menu
if "%MODO%"=="2" set "EXEC_MODE=SEGURO"& call :log "Modo alterado para SEGURO"& goto :menu
if "%MODO%"=="3" set "EXEC_MODE=REMOTO"& call :log "Modo alterado para REMOTO"& goto :menu
if "%MODO%"=="0" goto :menu
goto :modo

:log
echo [%date% %time%] %~1
>>"%LOG%" echo [%date% %time%] %~1
exit /b

:warn
set /a WARNINGS+=1
call :log "AVISO: %~1"
exit /b

:error
set /a ERRORS+=1
call :log "ERRO: %~1"
exit /b

:run
call :log "Executando: %~1"
echo [CMD] %~2
%~2 >>"%LOG%" 2>&1
if errorlevel 1 (
    call :warn "comando terminou com erro ou retorno diferente de zero: %~1"
) else (
    call :log "OK: %~1"
)
exit /b

:run_soft
call :log "Executando (idempotente): %~1"
%~2 >>"%LOG%" 2>&1
if errorlevel 1 (
    call :log "INFO: retorno diferente de zero ignorado por ser comando idempotente: %~1"
) else (
    call :log "OK: %~1"
)
exit /b

:ps
call :log "PowerShell: %~1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "%~2" >>"%LOG%" 2>&1
if errorlevel 1 (
    call :warn "PowerShell retornou erro: %~1"
) else (
    call :log "OK: %~1"
)
exit /b

:ps_soft
call :log "PowerShell (idempotente): %~1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "%~2" >>"%LOG%" 2>&1
if errorlevel 1 (
    call :log "INFO: retorno PowerShell diferente de zero ignorado por ser acao idempotente: %~1"
) else (
    call :log "OK: %~1"
)
exit /b

:confirmar
set "CONFIRM_RESULT=N"
set /p CONFIRM_INPUT=%~1 [S/N]: 
if /I "%CONFIRM_INPUT%"=="S" set "CONFIRM_RESULT=S"
if /I "%CONFIRM_INPUT%"=="SIM" set "CONFIRM_RESULT=S"
if /I "%CONFIRM_INPUT%"=="Y" set "CONFIRM_RESULT=S"
if /I "%CONFIRM_INPUT%"=="YES" set "CONFIRM_RESULT=S"
exit /b

:diagnostico_inicial_silencioso
>>"%LOG%" echo.
>>"%LOG%" echo ===== DIAGNOSTICO INICIAL BASICO =====
ver >>"%LOG%" 2>&1
hostname >>"%LOG%" 2>&1
whoami >>"%LOG%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture | Format-List; Get-PSDrive -PSProvider FileSystem | Format-Table Name,Used,Free,Root -Auto; powercfg /getactivescheme" >>"%LOG%" 2>&1
>>"%LOG%" echo ===== FIM DIAGNOSTICO INICIAL BASICO =====
exit /b

:diagnostico
call :banner
call :log "Modulo DIAGNOSTICO COMPLETO iniciado"
call :run "Informacoes do sistema" "systeminfo"
call :run "Configuracao de rede completa" "ipconfig /all"
call :ps "Inventario tecnico PowerShell" "Get-CimInstance Win32_ComputerSystem ^| Format-List Manufacturer,Model,TotalPhysicalMemory; Get-CimInstance Win32_BIOS ^| Format-List SerialNumber,SMBIOSBIOSVersion; Get-CimInstance Win32_OperatingSystem ^| Format-List Caption,Version,BuildNumber,InstallDate,LastBootUpTime; Get-PSDrive -PSProvider FileSystem ^| Format-Table Name,Used,Free,Root -Auto; Get-Service spooler,wuauserv,bits,dosvc,cryptsvc,VSS -ErrorAction SilentlyContinue ^| Format-Table Name,Status,StartType -Auto; Get-Printer -ErrorAction SilentlyContinue ^| Format-Table Name,DriverName,PortName,PrinterStatus,WorkOffline -Auto"
call :ps "Teste DNS e HTTPS" "Test-NetConnection google.com -Port 443; nslookup google.com"
echo.
echo ===== RESUMO DIAGNOSTICO (TELA) =====
echo.
hostname
whoami
ver
ipconfig | findstr /I "IPv4 IPv6 Gateway DNS"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture | Format-List; Get-PSDrive -PSProvider FileSystem | Format-Table Name,Used,Free,Root -Auto; Get-Service spooler,wuauserv,bits,dosvc,cryptsvc,VSS -ErrorAction SilentlyContinue | Format-Table Name,Status,StartType -Auto"
echo.
echo ===== FIM RESUMO DIAGNOSTICO =====
call :log "Modulo DIAGNOSTICO COMPLETO finalizado"
goto :final_modulo

:run_dism_single
if exist "%DISM_LOCK_DIR%" (
    call :warn "DISM ja esta em execucao por outra tarefa. Etapa ignorada: %~1"
    exit /b 0
)
mkdir "%DISM_LOCK_DIR%" >nul 2>&1
if errorlevel 1 (
    call :warn "Nao foi possivel obter lock do DISM. Etapa ignorada: %~1"
    exit /b 0
)
call :run "%~1" "%~2"
rmdir "%DISM_LOCK_DIR%" >nul 2>&1
exit /b 0

:criar_ponto_restauracao
call :ps "Criar ponto de restauracao" "try { $p='OtimizacaoTI-V4-' + (Get-Date -Format yyyy-MM-dd-HHmm); Enable-ComputerRestore -Drive $env:SystemDrive'\' -ErrorAction SilentlyContinue; Set-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name SystemRestorePointCreationFrequency -Value 0 -Force -ErrorAction SilentlyContinue; Checkpoint-Computer -Description $p -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Write-Output ('Ponto criado: ' + $p) } catch { Write-Output ('Nao foi possivel criar ponto de restauracao: ' + $_.Exception.Message); exit 1 }"
exit /b

:limpeza
call :banner
call :log "Modulo LIMPEZA iniciado"
call :ps "Espaco em disco antes da limpeza" "Get-PSDrive -PSProvider FileSystem ^| Format-Table Name,Used,Free,Root -Auto"

call :confirmar "Deseja fechar navegadores para liberar cache?"
if /I "%CONFIRM_RESULT%"=="S" (
    echo [1/13] Fechando processos de navegadores...
    call :run_soft "Fechar Chrome" "taskkill /f /im chrome.exe"
    call :run_soft "Fechar Edge" "taskkill /f /im msedge.exe"
    call :run_soft "Fechar Brave" "taskkill /f /im brave.exe"
    call :run_soft "Fechar Firefox" "taskkill /f /im firefox.exe"
    call :run_soft "Fechar Opera" "taskkill /f /im opera.exe"
    call :run_soft "Fechar Vivaldi" "taskkill /f /im vivaldi.exe"
) else (
    call :warn "Fechamento de navegadores ignorado pelo usuario"
)

echo [2/13] Limpando temporarios do Windows...
call :ps "Limpar TEMP do Windows" "$paths=@($env:TEMP,$env:TMP,(Join-Path $env:windir 'Temp')); foreach($p in $paths){ if(Test-Path -LiteralPath $p){ Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue ^| ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } } }"

echo [3/13] Limpando temporarios de todos os usuarios...
call :ps "Limpar TEMP dos usuarios" "$base=Join-Path $env:SystemDrive 'Users'; $skip=@('Public','Default','Default User','All Users'); Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue ^| Where-Object { $skip -notcontains $_.Name } ^| ForEach-Object { $u=$_; @('AppData\Local\Temp','AppData\Local\Microsoft\Windows\INetCache','AppData\Local\Microsoft\Windows\WebCache','AppData\Local\CrashDumps') ^| ForEach-Object { $p=Join-Path $u.FullName $_; if(Test-Path -LiteralPath $p){ Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue ^| ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } } } }"

echo [4/13] Limpando cache de todos os perfis de navegadores Chromium/Firefox...
call :ps "Limpar cache de navegadores multi-perfil" "$base=Join-Path $env:SystemDrive 'Users'; $skip=@('Public','Default','Default User','All Users'); $roots=@('AppData\Local\Google\Chrome\User Data','AppData\Local\Microsoft\Edge\User Data','AppData\Local\BraveSoftware\Brave-Browser\User Data','AppData\Local\Vivaldi\User Data','AppData\Roaming\Opera Software\Opera Stable'); $cacheNames=@('Cache','Code Cache','GPUCache','Service Worker\CacheStorage','DawnCache','ShaderCache','GrShaderCache'); Get-ChildItem -LiteralPath $base -Directory -Force -EA SilentlyContinue ^| Where-Object { $skip -notcontains $_.Name } ^| ForEach-Object { $u=$_; foreach($rootRel in $roots){ $root=Join-Path $u.FullName $rootRel; if(Test-Path $root){ Get-ChildItem $root -Directory -EA SilentlyContinue ^| ForEach-Object { $profile=$_; foreach($c in $cacheNames){ $p=Join-Path $profile.FullName $c; if(Test-Path $p){ Get-ChildItem $p -Force -EA SilentlyContinue ^| Remove-Item -Recurse -Force -EA SilentlyContinue } } } } }; $ff=Join-Path $u.FullName 'AppData\Local\Mozilla\Firefox\Profiles'; if(Test-Path $ff){ Get-ChildItem $ff -Directory -EA SilentlyContinue ^| ForEach-Object { foreach($folder in @('cache2','startupCache')){ $p=Join-Path $_.FullName $folder; if(Test-Path $p){ Get-ChildItem $p -Force -EA SilentlyContinue ^| Remove-Item -Recurse -Force -EA SilentlyContinue } } } }; $d3d=Join-Path $u.FullName 'AppData\Local\D3DSCache'; if(Test-Path $d3d){ Get-ChildItem $d3d -Force -EA SilentlyContinue ^| Remove-Item -Recurse -Force -EA SilentlyContinue } }"

echo [5/13] Limpando cache do Windows Update...
call :run "Parar Windows Update" "net stop wuauserv /y"
call :run "Parar BITS" "net stop bits /y"
call :run "Parar Delivery Optimization" "net stop dosvc /y"
call :run "Parar CryptSvc" "net stop cryptsvc /y"
if exist "%windir%\SoftwareDistribution\Download" rd /s /q "%windir%\SoftwareDistribution\Download" >>"%LOG%" 2>&1
mkdir "%windir%\SoftwareDistribution\Download" >nul 2>&1
if exist "%ProgramData%\Microsoft\Windows\DeliveryOptimization\Cache" rd /s /q "%ProgramData%\Microsoft\Windows\DeliveryOptimization\Cache" >>"%LOG%" 2>&1
mkdir "%ProgramData%\Microsoft\Windows\DeliveryOptimization\Cache" >nul 2>&1
call :run "Iniciar CryptSvc" "net start cryptsvc"
call :run "Iniciar Delivery Optimization" "net start dosvc"
call :run "Iniciar BITS" "net start bits"
call :run "Iniciar Windows Update" "net start wuauserv"

echo [6/13] Limpando relatorios de erro e dumps antigos...
call :ps "Limpar WER e dumps" "$paths=@((Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),(Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'),(Join-Path $env:windir 'Minidump'),(Join-Path $env:windir 'LiveKernelReports')); foreach($p in $paths){ if(Test-Path -LiteralPath $p){ Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue ^| Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } ^| Remove-Item -Recurse -Force -EA SilentlyContinue } }"

echo [7/13] Limpando miniaturas e caches graficos...
call :ps "Limpar thumbnails e icon cache" "$base=Join-Path $env:SystemDrive 'Users'; $skip=@('Public','Default','Default User','All Users'); Get-ChildItem -LiteralPath $base -Directory -Force -EA SilentlyContinue ^| Where-Object { $skip -notcontains $_.Name } ^| ForEach-Object { $exp=Join-Path $_.FullName 'AppData\Local\Microsoft\Windows\Explorer'; if(Test-Path $exp){ Get-ChildItem $exp -Force -EA SilentlyContinue -Include 'thumbcache_*.db','iconcache_*.db' ^| Remove-Item -Force -EA SilentlyContinue } }"

call :confirmar "Deseja esvaziar a lixeira?"
if /I "%CONFIRM_RESULT%"=="S" (
    echo [8/13] Limpando lixeira...
    call :ps "Limpar lixeira" "Clear-RecycleBin -Force -ErrorAction SilentlyContinue"
) else (
    call :warn "Limpeza da lixeira ignorada pelo usuario"
)

echo [9/13] Limpando componentes antigos do Windows...
call :run_dism_single "DISM StartComponentCleanup" "dism /Online /Cleanup-Image /StartComponentCleanup"

echo [10/13] Executando Limpeza de Disco automatica com todos os itens marcados...
call :ps "Cleanmgr automatico com todas as categorias" "$cleanmgr=Join-Path $env:windir 'System32\cleanmgr.exe'; if(Test-Path -LiteralPath $cleanmgr){ $flag='StateFlags0099'; $base='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'; Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue ^| ForEach-Object { New-ItemProperty -LiteralPath $_.PSPath -Name $flag -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue ^| Out-Null }; Start-Process -FilePath $cleanmgr -ArgumentList '/sagerun:99' -Wait -NoNewWindow; Write-Output 'Cleanmgr finalizado com StateFlags0099=2 em todas as categorias disponiveis.' } else { Write-Output 'cleanmgr.exe nao encontrado neste Windows.' }"

echo [11/13] Limpando cache DNS...
call :run "Flush DNS" "ipconfig /flushdns"

echo [12/13] Otimizando cache de componentes e arquivos temporarios residuais...
call :ps "Limpeza residual segura" "Get-ChildItem $env:ProgramData -Directory -EA SilentlyContinue ^| Where-Object Name -match 'Package Cache|Temp' ^| ForEach-Object { Write-Output ('Pasta mantida para seguranca: ' + $_.FullName) }"

echo [13/13] Calculando espaco em disco apos limpeza...
call :ps "Espaco em disco depois da limpeza" "Get-PSDrive -PSProvider FileSystem ^| Format-Table Name,Used,Free,Root -Auto"
call :log "Modulo LIMPEZA finalizado"
goto :final_modulo

:otimizacao
call :banner
call :log "Modulo OTIMIZACAO iniciado"
call :criar_ponto_restauracao

echo [1/8] Criando e ativando plano de energia Desempenho Maximo...
call :ps "Ativar plano Desempenho Maximo" "$before=(powercfg /getactivescheme) -join ' '; Write-Output ('Plano anterior: ' + $before); $out=powercfg -duplicatescheme E9A42B02-D5DF-448D-AA00-03F14749EB61; $txt=$out -join ' '; $m=[regex]::Match($txt,'[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}'); if($m.Success){ powercfg /setactive $m.Value; Write-Output ('Plano ativo: ' + $m.Value) } else { powercfg /setactive E9A42B02-D5DF-448D-AA00-03F14749EB61; Write-Output 'Tentativa de ativacao direta do plano Desempenho Maximo.' }; powercfg /getactivescheme"

echo [2/8] Ajustando energia para performance em AC...
call :run "Desativar desligamento de disco em AC" "powercfg /change disk-timeout-ac 0"
call :run "Desativar suspensao em AC" "powercfg /change standby-timeout-ac 0"
call :run "Desativar hibernacao por timeout em AC" "powercfg /change hibernate-timeout-ac 0"

echo [3/8] Detectando notebook e registrando aviso...
call :ps "Detectar notebook" "$b=Get-CimInstance Win32_Battery -EA SilentlyContinue; if($b){ Write-Output 'Notebook detectado: Desempenho Maximo mantido por solicitacao do usuario; consumo e temperatura podem aumentar.' } else { Write-Output 'Notebook nao detectado.' }"

echo [4/8] Reparando imagem do Windows com DISM...
call :run_dism_single "DISM RestoreHealth" "dism /Online /Cleanup-Image /RestoreHealth"

echo [5/8] Verificando arquivos do sistema com SFC...
call :run "SFC Scannow" "sfc /scannow"

echo [6/8] Otimizando discos SSD/HDD...
call :ps "Optimize-Volume em unidades fixas" "$vols=Get-Volume -ErrorAction SilentlyContinue; foreach($v in $vols){ if($v.DriveLetter -and $v.DriveType -eq 'Fixed'){ Write-Output ('Otimizando unidade ' + $v.DriveLetter + ':'); Optimize-Volume -DriveLetter $v.DriveLetter -Verbose -ErrorAction SilentlyContinue } }"

echo [7/8] Atualizando politicas de grupo...
call :run "GPUpdate Force" "gpupdate /force"

echo [8/8] Limpando DNS novamente...
call :run "Flush DNS final" "ipconfig /flushdns"
set "REBOOT_RECOMMENDED=1"
call :log "Modulo OTIMIZACAO finalizado"
goto :final_modulo

:rede
call :banner
call :log "Modulo REDE iniciado"
echo ATENCAO: reparo de rede pode derrubar VPN, RDP, AnyDesk ou TeamViewer.
if /I "%EXEC_MODE%"=="REMOTO" (
    call :warn "Modo REMOTO ativo: comandos que derrubam conexao serao ignorados"
) else (
    call :confirmar "Deseja continuar com reparo de rede completo?"
    if /I not "%CONFIRM_RESULT%"=="S" goto :menu
)

echo [1/12] Limpando DNS...
call :run "Flush DNS" "ipconfig /flushdns"
echo [2/12] Registrando DNS...
call :run "Register DNS" "ipconfig /registerdns"

if /I not "%EXEC_MODE%"=="REMOTO" (
    echo [3/12] Liberando IP...
    call :run "Release IP" "ipconfig /release"
    echo [4/12] Renovando IP...
    call :run "Renew IP" "ipconfig /renew"
) else (
    call :warn "ipconfig release/renew ignorado em Modo REMOTO"
)

echo [5/12] Limpando ARP e cache de destino...
call :run "Limpar ARP" "arp -d *"
call :run "Limpar ARP cache netsh" "netsh interface ip delete arpcache"
call :run "Limpar destination cache" "netsh interface ip delete destinationcache"

echo [6/12] Limpando NetBIOS...
call :run "NBTSTAT -R" "nbtstat -R"
call :run "NBTSTAT -RR" "nbtstat -RR"

if /I not "%EXEC_MODE%"=="REMOTO" (
    echo [7/12] Resetando TCP/IP...
    call :run "Reset TCP IP" "netsh int ip reset"
    echo [8/12] Resetando Winsock...
    call :run "Reset Winsock Catalog" "netsh winsock reset catalog"
    call :run "Reset Winsock" "netsh winsock reset"
    set "REBOOT_RECOMMENDED=1"
) else (
    call :warn "Reset TCP/IP e Winsock ignorados em Modo REMOTO"
)

echo [9/12] Resetando proxy WinHTTP...
call :run "Reset WinHTTP Proxy" "netsh winhttp reset proxy"
echo [10/12] Testando loopback e internet por IP...
call :run "Ping loopback" "ping 127.0.0.1 -n 2"
call :run "Ping 8.8.8.8" "ping 8.8.8.8 -n 2"
echo [11/12] Testando DNS por dominio...
call :run "Ping google.com" "ping google.com -n 2"
call :run "NSLookup google.com" "nslookup google.com"
echo [12/12] Salvando configuracao de rede...
call :run "IPConfig All" "ipconfig /all"
call :ps "Teste HTTPS porta 443" "Test-NetConnection google.com -Port 443"
call :log "Modulo REDE finalizado"
goto :final_modulo

:impressora
call :banner
call :log "Modulo IMPRESSORA iniciado"

echo [1/9] Listando impressoras instaladas...
call :ps "Inventario de impressoras" "try { Get-Printer -ErrorAction Stop ^| Format-Table Name,DriverName,PortName,PrinterStatus,WorkOffline -Auto } catch { Get-CimInstance Win32_Printer ^| Format-Table Name,DriverName,PortName,PrinterStatus,WorkOffline -Auto }"

echo [2/9] Removendo trabalhos presos nas filas...
call :ps "Limpar filas de impressao" "try { $printers=Get-Printer -ErrorAction Stop; foreach($p in $printers){ Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue ^| ForEach-Object { Remove-PrintJob -PrinterName $p.Name -ID $_.ID -ErrorAction SilentlyContinue; Write-Output ('Job removido: ' + $p.Name + ' ID ' + $_.ID) } } } catch { Write-Output 'Get-PrintJob indisponivel ou sem jobs.' }"

echo [3/9] Parando Spooler...
call :run "Parar Spooler" "net stop spooler /y"
timeout /t 2 >nul

echo [4/9] Limpando pasta de spool...
if exist "%windir%\System32\spool\PRINTERS" (
    del /f /s /q "%windir%\System32\spool\PRINTERS\*.*" >>"%LOG%" 2>&1
)

echo [5/9] Configurando Spooler como automatico...
call :run "Spooler automatico" "sc config spooler start= auto"

echo [6/9] Reiniciando servicos relacionados...
call :run "Iniciar RPCSS" "net start rpcss"
call :run "Iniciar Spooler" "net start spooler"
call :run "Iniciar fdPHost" "net start fdPHost"
call :run "Iniciar FDResPub" "net start FDResPub"
call :run "Iniciar SSDPSRV" "net start SSDPSRV"
call :run "Iniciar upnphost" "net start upnphost"
call :run "Iniciar LanmanWorkstation" "net start LanmanWorkstation"

echo [7/9] Validando spoolsv.exe...
call :run "SFC spoolsv.exe" "sfc /scanfile=%windir%\System32\spoolsv.exe"

echo [8/9] Testando servico spooler...
call :ps "Status Spooler" "Get-Service spooler ^| Format-List Name,Status,StartType"

echo [9/9] Relatorio final de impressoras...
call :ps "Relatorio final de impressoras" "try { Get-Printer -ErrorAction Stop ^| Format-Table Name,DriverName,PortName,PrinterStatus,WorkOffline -Auto } catch { Get-CimInstance Win32_Printer ^| Format-Table Name,DriverName,PortName,PrinterStatus,WorkOffline -Auto }"
call :log "Modulo IMPRESSORA finalizado"
goto :final_modulo

:ia_menu
call :banner
echo REMOVER RECURSOS DE IA DO WINDOWS
echo.
echo [1] Diagnosticar recursos de IA instalados
echo [2] Desativar IA por politicas e registro
echo [3] Remover Copilot, Recall e pacotes Appx de IA
echo [4] Remover pacotes CBS e arquivos protegidos de IA ^(avancado^)
echo [5] Bloquear reinstalacao apos Windows Update
echo [6] Executar remocao completa de IA
echo [7] Reverter politicas/registro de IA ^(nao reinstala pacotes removidos^)
echo [8] DRY-RUN completo de IA ^(somente relatorio^)
echo [0] Voltar
echo.
set /p IAOP=Digite a opcao: 
if "%IAOP%"=="0" goto :menu
if not exist "%AI_MODULE%" (
    call :error "Modulo de IA nao encontrado: %AI_MODULE%"
    pause
    goto :menu
)
if "%IAOP%"=="1" call :psfile_ai "Diagnosticar IA" "Diagnose" ""
if "%IAOP%"=="2" call :psfile_ai "Desativar IA por politicas" "DisablePolicies" ""
if "%IAOP%"=="3" call :ia_confirm_and_run "Remover Appx e Recall" "RemoveAppxAndRecall"
if "%IAOP%"=="4" call :ia_confirm_and_run "Remocao profunda CBS/arquivos" "RemoveDeep"
if "%IAOP%"=="5" call :psfile_ai "Bloquear reinstalacao pos-update" "PreventReinstall" ""
if "%IAOP%"=="6" call :ia_confirm_and_run "Remocao completa de IA" "All"
if "%IAOP%"=="7" call :psfile_ai "Reverter politicas de IA" "RevertPolicies" ""
if "%IAOP%"=="8" call :psfile_ai "Dry-run completo de IA" "All" "" "-DryRun"
goto :final_modulo

:ia_confirm_and_run
echo.
echo ATENCAO: %~1 altera/removera componentes do Windows.
echo Um ponto de restauracao e backups de registro serao criados quando possivel.
echo Gerando DRY-RUN automatico primeiro ^(somente relatorio, sem alterar^).
call :psfile_ai "Dry-run previo IA: %~1" "%~2" "" "-DryRun"
echo Para confirmar, digite exatamente: REMOVER IA
echo.
set /p IACONF=Confirmacao: 
if not "%IACONF%"=="REMOVER IA" (
    call :warn "Acao de IA cancelada por confirmacao invalida"
    goto :menu
)
call :psfile_ai "%~1" "%~2" "REMOVER IA"
exit /b

:psfile_ai
call :task_lock_acquire "ia_%~2"
if errorlevel 1 (
    call :warn "Funcao IA '%~2' ja esta em execucao em outra janela. Solicita????o ignorada."
    exit /b 1
)
call :log "Modulo IA: %~1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%AI_MODULE%" -Action "%~2" -LogPath "%LOG%" -ConfirmText "%~3" %~4
if errorlevel 1 (
    call :warn "Modulo IA retornou erro: %~1"
) else (
    call :log "OK: Modulo IA: %~1"
)
call :task_lock_release "ia_%~2"
set "REBOOT_RECOMMENDED=1"
exit /b

:otimizar_inicializacao
call :banner
call :log "Modulo OTIMIZAR INICIALIZACAO iniciado"
echo OTIMIZAR INICIALIZACAO
echo.
echo Esta rotina aplica ajustes para iniciar mais rapido e reduzir carga visual.
echo.
echo Acoes:
echo - ajustar efeitos visuais para melhor desempenho no usuario atual;
echo - configurar o boot para usar o numero maximo de processadores logicos detectados;
echo - ativar Fast Startup quando disponivel;
echo - remover atraso de apps de inicializacao;
echo - desativar entradas de inicializacao Run/Startup Folder de usuarios e maquina com backup;
echo - registrar inventario das tarefas agendadas de inicializacao.
echo.
echo ATENCAO: programas removidos da inicializacao podem ser reativados depois pelo proprio app.
echo Backup sera salvo em: %BASE_DIR%\StartupBackup
echo Para confirmar, digite exatamente: OTIMIZAR INICIALIZACAO
set /p STARTCONF=Confirmacao: 
if not "%STARTCONF%"=="OTIMIZAR INICIALIZACAO" (
    call :warn "Otimizacao de inicializacao cancelada por confirmacao invalida"
    goto :final_modulo
)
call :criar_ponto_restauracao

echo [1/7] Ajustando efeitos visuais para melhor desempenho...
call :ps "Efeitos visuais para melhor desempenho" "New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Force ^| Out-Null; Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -Type DWord -Value 2; New-Item -Path 'HKCU:\Control Panel\Desktop' -Force ^| Out-Null; Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name DragFullWindows -Type String -Value '0'; Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name MenuShowDelay -Type String -Value '0'; New-Item -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Force ^| Out-Null; Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name MinAnimate -Type String -Value '0'; Write-Output 'Efeitos visuais configurados para melhor desempenho no usuario atual.'"

echo [2/7] Configurando boot com maximo de processadores detectados...
call :ps "BCDEdit numproc maximo detectado" "$cpu=(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors; if(-not $cpu -or $cpu -lt 1){ $cpu=[Environment]::ProcessorCount }; Write-Output ('Processadores logicos detectados: ' + $cpu); bcdedit /set '{current}' numproc $cpu"

echo [3/7] Ativando Fast Startup quando disponivel...
call :ps_soft "Ativar Fast Startup" "powercfg /hibernate on; New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Force ^| Out-Null; Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Type DWord -Value 1; Write-Output 'Fast Startup/Hiberboot habilitado.'"

echo [4/7] Removendo atraso de inicializacao de aplicativos...
call :ps "Remover StartupDelayInMSec" "New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Force ^| Out-Null; Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Name StartupDelayInMSec -Type DWord -Value 0; Write-Output 'StartupDelayInMSec definido como 0.'"

echo [5/7] Desativando entradas Run/RunOnce com backup...
call :ps "Backup e remocao de Run/RunOnce" "$backup=Join-Path $env:ProgramData ('OtimizacaoTI\StartupBackup\' + (Get-Date -Format yyyyMMdd_HHmmss)); New-Item -ItemType Directory -Force -Path $backup ^| Out-Null; $regFile=Join-Path $backup 'startup-run-backup.reg'; cmd /c ('reg export HKCU\Software\Microsoft\Windows\CurrentVersion\Run ""' + $regFile + '"" /y') ^| Out-Null; cmd /c ('reg export HKLM\Software\Microsoft\Windows\CurrentVersion\Run ""' + (Join-Path $backup 'startup-run-hklm-backup.reg') + '"" /y') ^| Out-Null; $keys=@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'); foreach($k in $keys){ if(Test-Path $k){ $item=Get-ItemProperty -Path $k; $item.PSObject.Properties ^| Where-Object { $_.Name -notmatch '^PS' -and $_.Name -notin @('SecurityHealth','SecurityHealthSystray') } ^| ForEach-Object { Write-Output ('Removendo inicializacao: ' + $k + '\' + $_.Name); Remove-ItemProperty -Path $k -Name $_.Name -Force -ErrorAction SilentlyContinue } } }; Write-Output ('Backup salvo em: ' + $backup)"

echo [6/7] Movendo atalhos das pastas Startup com backup...
call :ps "Mover atalhos Startup Folder" "$backup=Join-Path $env:ProgramData ('OtimizacaoTI\StartupBackup\' + (Get-Date -Format yyyyMMdd_HHmmss) + '\StartupFolders'); New-Item -ItemType Directory -Force -Path $backup ^| Out-Null; $folders=@([Environment]::GetFolderPath('Startup'),[Environment]::GetFolderPath('CommonStartup')); foreach($folder in $folders){ if($folder -and (Test-Path -LiteralPath $folder)){ $dest=Join-Path $backup (($folder -replace '[:\\\/]','_')); New-Item -ItemType Directory -Force -Path $dest ^| Out-Null; Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue ^| ForEach-Object { Write-Output ('Movendo item Startup: ' + $_.FullName); Move-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction SilentlyContinue } } }; Write-Output ('Backup das pastas Startup salvo em: ' + $backup)"

echo [7/7] Registrando tarefas agendadas de inicializacao para revisao...
call :ps "Inventario de tarefas de inicializacao" "$backup=Join-Path $env:ProgramData 'OtimizacaoTI\StartupBackup'; New-Item -ItemType Directory -Force -Path $backup ^| Out-Null; $out=Join-Path $backup ('scheduled-startup-tasks-' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt'); Get-ScheduledTask ^| Where-Object { $_.Triggers -and ($_.Triggers ^| Where-Object { $_.CimClass.CimClassName -match 'Logon|Boot|Startup' }) } ^| Select-Object TaskName,TaskPath,State ^| Format-Table -AutoSize ^| Out-String ^| Set-Content -Path $out -Encoding UTF8; Write-Output ('Inventario salvo em: ' + $out)"

set "REBOOT_RECOMMENDED=1"
call :log "Modulo OTIMIZAR INICIALIZACAO finalizado"
goto :final_modulo

:tools_menu
call :banner
echo FERRAMENTAS PORTATEIS
echo.
echo [1] Abrir CrystalDiskInfo Portable
echo [2] Abrir TreeSize Free Portable
echo [3] Abrir Dism++ ^(usa config local, limpeza agressiva pre-configurada^)
echo [4] Abrir Revo Uninstaller Pro 5.4.7
echo [0] Voltar
echo.
set /p TOP=Digite a opcao: 
if "%TOP%"=="0" goto :menu
if "%TOP%"=="1" call :launch_portable "CrystalDiskInfo" "%TOOL_CDI%" "" & goto :final_modulo
if "%TOP%"=="2" call :launch_portable "TreeSizeFree" "%TOOL_TREE%" "" & goto :final_modulo
if "%TOP%"=="4" call :launch_portable "Revo Uninstaller Pro 5.4.7" "%TOOL_REVO%" "" & goto :final_modulo
if "%TOP%"=="3" goto :launch_dismpp
goto :tools_menu

:launch_dismpp
set "DISM_EXE="
if exist "%TOOL_DISM64%" set "DISM_EXE=%TOOL_DISM64%"
if not defined DISM_EXE if exist "%TOOL_DISM_ARM64%" set "DISM_EXE=%TOOL_DISM_ARM64%"
if not defined DISM_EXE if exist "%TOOL_DISM86%" set "DISM_EXE=%TOOL_DISM86%"
if not defined DISM_EXE (
    call :warn "Dism++ nao encontrado em %TOOLS_DIR%\DismPP"
    goto :final_modulo
)
echo.
echo ATENCAO: Dism++ esta com limpeza agressiva pre-configurada.
echo.
echo [S] Abrir Dism++
echo [V] Voltar ao menu de ferramentas
choice /c SV /n /m "Escolha uma opcao [S/V]: "
if errorlevel 2 (
    call :log "Abertura do Dism++ cancelada pelo usuario (V)"
    goto :final_modulo
)
call :launch_portable "Dism++" "%DISM_EXE%" ""
goto :final_modulo

:launch_portable
if not exist "%~2" (
    call :warn "Ferramenta nao encontrada: %~2"
    exit /b 1
)
call :log "Abrindo ferramenta portatil: %~1 (%~2)"
start "" "%~2" %~3
if errorlevel 1 (
    call :warn "Falha ao abrir ferramenta portatil: %~1"
) else (
    call :log "OK: ferramenta portatil aberta: %~1"
)
exit /b 0

:users_menu
call :banner
echo SESSOES DE USUARIO
echo.
echo [1] Listar sessoes atuais ^(quser^)
echo [2] Forcar logoff de outros usuarios ^(nao encerra a sessao atual^)
echo [0] Voltar
echo.
set /p UOP=Digite a opcao: 
if "%UOP%"=="0" goto :menu
if "%UOP%"=="1" goto :users_list
if "%UOP%"=="2" goto :users_logoff
goto :users_menu

:users_list
call :log "Listando sessoes de usuario com quser"
quser
quser >>"%LOG%" 2>&1
goto :final_modulo

:users_logoff
echo.
echo ATENCAO: esta acao desconecta outros usuarios conectados neste equipamento.
echo Para confirmar, digite exatamente: LOGOFF FORCADO
set /p LOGOFFCONF=Confirmacao: 
if /I not "%LOGOFFCONF%"=="LOGOFF FORCADO" (
    call :warn "Logoff forcado cancelado por confirmacao invalida"
    goto :final_modulo
)
call :ps "Forcar logoff de outros usuarios" "$sessions = quser 2>$null; if (-not $sessions) { Write-Output 'Nenhuma sessao encontrada.'; exit 0 }; $found = $false; for ($i=1; $i -lt $sessions.Count; $i++) { $line = $sessions[$i]; if ($line -notmatch '^\s*>') { $parts = $line.Trim() -split '\s+'; $id = $null; $user = $parts[0]; for ($j=1; $j -lt $parts.Count; $j++) { if ($parts[$j] -match '^\d+$') { $id = $parts[$j]; break } }; if ($id) { $found = $true; Write-Output ('Desconectando: ' + $user + ' (ID: ' + $id + ')'); logoff $id } } }; if (-not $found) { Write-Output 'Nenhum outro usuario conectado para logoff.' }"
set "REBOOT_RECOMMENDED=1"
goto :final_modulo

:inventario_live
call :log "Inventario LIVE iniciado"
if not exist "%INVENTARIO_PS1%" (
    call :error "Modulo Inventario nao encontrado: %INVENTARIO_PS1%"
    goto :final_modulo
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%INVENTARIO_PS1%" -OutputPath "%INVENTARIO_LOG_DIR%"
if errorlevel 1 (
    call :warn "Inventario LIVE finalizou com erro."
) else (
    call :log "OK: Inventario LIVE finalizado"
)
goto :final_modulo

:tudo_rapido
call :banner
call :log "Execucao MANUTENCAO RAPIDA COMPLETA iniciada"
call :limpeza_sem_menu
call :otimizacao_sem_menu
call :rede_sem_menu
call :impressora_sem_menu
call :log "Execucao MANUTENCAO RAPIDA COMPLETA finalizada"
goto :final_modulo

:tudo_completo
call :banner
call :log "Execucao MANUTENCAO COMPLETA AVANCADA iniciada"
call :confirmar "A manutencao completa pode demorar e alterar rede/servicos. Continuar?"
if /I not "%CONFIRM_RESULT%"=="S" goto :menu
call :limpeza_sem_menu
call :otimizacao_sem_menu
call :rede_sem_menu
call :impressora_sem_menu
call :diagnostico_inicial_silencioso
call :log "Execucao MANUTENCAO COMPLETA AVANCADA finalizada"
goto :final_modulo

:limpeza_sem_menu
call :log "Execucao rapida: LIMPEZA"
call :ps "Limpeza geral rapida" "$paths=@($env:TEMP,$env:TMP,(Join-Path $env:windir 'Temp')); foreach($p in $paths){ if(Test-Path -LiteralPath $p){ Get-ChildItem -LiteralPath $p -Force -EA SilentlyContinue ^| Remove-Item -Recurse -Force -EA SilentlyContinue } }; Clear-RecycleBin -Force -EA SilentlyContinue"
call :run "Parar Windows Update" "net stop wuauserv /y"
call :run "Parar BITS" "net stop bits /y"
if exist "%windir%\SoftwareDistribution\Download" rd /s /q "%windir%\SoftwareDistribution\Download" >>"%LOG%" 2>&1
mkdir "%windir%\SoftwareDistribution\Download" >nul 2>&1
call :run "Iniciar BITS" "net start bits"
call :run "Iniciar Windows Update" "net start wuauserv"
call :run "Flush DNS" "ipconfig /flushdns"
exit /b

:otimizacao_sem_menu
call :log "Execucao rapida: OTIMIZACAO"
call :ps "Ativar plano Desempenho Maximo" "$out=powercfg -duplicatescheme E9A42B02-D5DF-448D-AA00-03F14749EB61; $txt=$out -join ' '; $m=[regex]::Match($txt,'[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}'); if($m.Success){ powercfg /setactive $m.Value } else { powercfg /setactive E9A42B02-D5DF-448D-AA00-03F14749EB61 }"
call :run_dism_single "DISM StartComponentCleanup" "dism /Online /Cleanup-Image /StartComponentCleanup"
call :run_dism_single "DISM RestoreHealth" "dism /Online /Cleanup-Image /RestoreHealth"
call :run "SFC Scannow" "sfc /scannow"
call :ps "Optimize-Volume" "$vols=Get-Volume -EA SilentlyContinue; foreach($v in $vols){ if($v.DriveLetter -and $v.DriveType -eq 'Fixed'){ Optimize-Volume -DriveLetter $v.DriveLetter -Verbose -EA SilentlyContinue } }"
set "REBOOT_RECOMMENDED=1"
exit /b

:rede_sem_menu
call :log "Execucao rapida: REDE"
call :run "Flush DNS" "ipconfig /flushdns"
call :run "Register DNS" "ipconfig /registerdns"
call :run "Limpar ARP" "arp -d *"
call :run "Limpar ARP cache netsh" "netsh interface ip delete arpcache"
if /I not "%EXEC_MODE%"=="REMOTO" (
    call :run "Reset TCP IP" "netsh int ip reset"
    call :run "Reset Winsock" "netsh winsock reset"
    set "REBOOT_RECOMMENDED=1"
) else (
    call :warn "Reset TCP/IP e Winsock ignorados em Modo REMOTO"
)
call :run "Reset WinHTTP Proxy" "netsh winhttp reset proxy"
exit /b

:impressora_sem_menu
call :log "Execucao rapida: IMPRESSORA"
call :ps "Limpar jobs impressora" "try { Get-Printer -EA Stop ^| ForEach-Object { $p=$_; Get-PrintJob -PrinterName $p.Name -EA SilentlyContinue ^| ForEach-Object { Remove-PrintJob -PrinterName $p.Name -ID $_.ID -EA SilentlyContinue } } } catch {}"
call :run "Parar Spooler" "net stop spooler /y"
if exist "%windir%\System32\spool\PRINTERS" del /f /s /q "%windir%\System32\spool\PRINTERS\*.*" >>"%LOG%" 2>&1
call :run "Spooler automatico" "sc config spooler start= auto"
call :run "Iniciar Spooler" "net start spooler"
exit /b

:resumo_final
call :log "============================================================"
call :log "RESUMO DA EXECUCAO"
call :log "Avisos: %WARNINGS%"
call :log "Erros: %ERRORS%"
call :log "Reinicio recomendado: %REBOOT_RECOMMENDED%"
call :log "============================================================"
exit /b

:pergunta_reinicio
set "REBOOT=N"
if "%REBOOT_RECOMMENDED%"=="1" (
    echo.
    echo Reinicio recomendado para concluir alteracoes.
)
set /p REBOOT=Deseja reiniciar agora? [S/N]: 
if /I "%REBOOT%"=="S" goto :reiniciar
if /I "%REBOOT%"=="SIM" goto :reiniciar
if /I "%REBOOT%"=="Y" goto :reiniciar
if /I "%REBOOT%"=="YES" goto :reiniciar
exit /b

:reiniciar
call :log "Reinicio solicitado pelo usuario"
shutdown /r /t 30 /c "OTIMIZACAO TI V4 PLUS: reinicio solicitado."
exit /b

:final_modulo
call :resumo_final
if defined WORKER_TASK goto :worker_end
echo.
echo Operacao finalizada.
echo Log salvo em: %LOG%
echo.
echo ===== ULTIMAS LINHAS DO LOG =====
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%LOG%' -Tail 30"
echo ===== FIM DO RESUMO =====
echo.
goto :menu

:worker_end
if defined HELD_TASK_LOCK_NAME call :task_lock_release "%HELD_TASK_LOCK_NAME%"
call :log "Worker finalizado: %WORKER_TASK%"
echo.
echo ===== ULTIMAS LINHAS DO LOG =====
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo ===== FIM DO RESUMO =====
echo.
echo Worker concluido. Esta janela permanecera aberta para consulta.
exit /b 0

:fim
call :log "OTIMIZACAO TI encerrado"
call :resumo_final
if not defined WORKER_TASK if exist "%LOCK_FILE%" del /f /q "%LOCK_FILE%" >nul 2>&1
echo.
echo Encerrado. Log salvo em:
echo %LOG%
echo.
pause
exit /b 0
