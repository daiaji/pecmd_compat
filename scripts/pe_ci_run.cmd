@echo off
REM pe_ci_run.cmd - run peshell test profile and output results to a CI drive
REM This script is started from SYSTEM\Setup\CmdLine through cmd.exe /c.

setlocal EnableExtensions
set "LOG=X:\Windows\Temp\pe_ci_result.log"
set "LOGDRIVE="
set "PESHELL_RC=not_started"

for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist %%D:\PE_CI_RESULT_DRIVE.TAG (
        set "LOG=%%D:\pe_ci_result.log"
        set "LOGDRIVE=%%D:"
    )
)

echo === CI RUN START === > "%LOG%"
echo LOG=%LOG% >> "%LOG%"
echo LOGDRIVE=%LOGDRIVE% >> "%LOG%"
echo SYSTEMROOT=%SYSTEMROOT% >> "%LOG%"
echo STAGE=check_files >> "%LOG%"
if defined LOGDRIVE dir /b "%LOGDRIVE%\PE_CI*.TAG" >> "%LOG%" 2>&1

if defined LOGDRIVE (
    if exist "%LOGDRIVE%\PE_CI_SERIAL_CMD.TAG" (
        echo STAGE=serial_cmd >> "%LOG%"
        X:\Windows\System32\serial_cmd.exe >> "%LOG%" 2>&1
        echo SERIAL_CMD_EXIT=%ERRORLEVEL% >> "%LOG%"
        goto :done
    )
    if exist "%LOGDRIVE%\PE_CI_SERIAL_BRIDGE.TAG" (
        echo STAGE=serial_bridge >> "%LOG%"
        X:\Windows\System32\serial_cmd.exe --autorun "X:\Windows\System32\peshell.exe run X:\Windows\System32\winpe_test_profile.lua" >> "%LOG%" 2>&1
        echo SERIAL_BRIDGE_EXIT=%ERRORLEVEL% >> "%LOG%"
        goto :done
    )
)

if not exist X:\Windows\System32\peshell.exe (
    echo ERROR: peshell.exe not found >> "%LOG%"
    goto :done
)

if not exist X:\Windows\System32\lua51.dll (
    echo ERROR: lua51.dll not found >> "%LOG%"
    goto :done
)

if not exist X:\Windows\System32\winpe_test_profile.lua (
    echo ERROR: winpe_test_profile.lua not found >> "%LOG%"
    goto :done
)

echo STAGE=before_peshell >> "%LOG%"
X:\Windows\System32\peshell.exe run X:\Windows\System32\winpe_test_profile.lua >> "%LOG%" 2>&1
set "PESHELL_RC=%ERRORLEVEL%"
echo STAGE=after_peshell >> "%LOG%"
echo PESHELL_EXIT=%PESHELL_RC% >> "%LOG%"

:done
echo STAGE=before_flush >> "%LOG%"
type "%LOG%" > NUL
ping -n 4 127.0.0.1 > NUL
echo === CI RUN DONE === >> "%LOG%"
type "%LOG%" > NUL
ping -n 3 127.0.0.1 > NUL
wpeutil reboot
