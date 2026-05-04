@echo off
REM ============================================================
REM EMI Locker Autonomous Builder
REM ============================================================
REM Runs the builder with the Codex live supervisor watcher enabled.
REM Executor and worker model IDs are configured in autonomous_builder.py.
REM ============================================================

setlocal

set PROJECT_DIR=.
set PHASE=
set START_MODULE=
set MAX_FIXES=2
set START_MONITOR=1

:parse_args
if "%~1"=="" goto :run
if "%~1"=="--project-dir" (
    set PROJECT_DIR=%~2
    shift
    shift
    goto :parse_args
)
if "%~1"=="--phase" (
    set PHASE=%~2
    shift
    shift
    goto :parse_args
)
if "%~1"=="--start-module" (
    set START_MODULE=%~2
    shift
    shift
    goto :parse_args
)
if "%~1"=="--max-fixes" (
    set MAX_FIXES=%~2
    shift
    shift
    goto :parse_args
)
if "%~1"=="--no-monitor" (
    set START_MONITOR=0
    shift
    goto :parse_args
)
if "%~1"=="--help" goto :help
echo Unknown argument: %~1
goto :help

:help
echo.
echo Usage: run_autonomous_build.bat [options]
echo.
echo Options:
echo   --project-dir DIR       Project directory (default: .)
echo   --phase N               Build only this phase
echo   --start-module NAME     Resume from a module name
echo   --max-fixes N           Max fix iterations per module (default: 2)
echo   --no-monitor            Do not start the browser monitor
echo   --help                  Show this help
echo.
echo Examples:
echo   run_autonomous_build.bat --phase 1 --start-module backend-auth
echo   run_autonomous_build.bat --phase 1 --max-fixes 2
echo.
exit /b 0

:run
echo.
echo ============================================================
echo EMI LOCKER AUTONOMOUS BUILDER
echo ============================================================
echo Project Directory: %PROJECT_DIR%
echo Phase: %PHASE%
echo Start Module: %START_MODULE%
echo Max Fixes: %MAX_FIXES%
echo Codex Supervisor Watcher: enabled
echo.

if "%START_MONITOR%"=="1" (
    echo Starting monitor at http://localhost:8080 ...
    start "EMI Monitor" /min cmd /c "cd /d %PROJECT_DIR% && node monitor\server.js"
)

set CMD=python autonomous_builder.py --project-dir "%PROJECT_DIR%" --max-fixes %MAX_FIXES%
if not "%PHASE%"=="" set CMD=%CMD% --phase %PHASE%
if not "%START_MODULE%"=="" set CMD=%CMD% --start-module "%START_MODULE%"

echo Running:
echo   %CMD%
echo.
%CMD%

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ============================================================
    echo BUILD COMPLETED
    echo ============================================================
    echo Check:
    echo   build_log.md
    echo   supervisor_reports\
    echo   SUPERVISOR_AUDIT.md
    echo.
) else (
    echo.
    echo ============================================================
    echo BUILD FAILED
    echo ============================================================
    echo Check build_log.md and supervisor_reports\.
    echo.
)

pause
