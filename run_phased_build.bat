@echo off
REM ============================================================
REM EMI Locker Phased Builder
REM ============================================================
REM Two AI models work together in phases:
REM   Phase 1: 50% - Core Architecture & Security
REM   Phase 2: 25% - Backend & API
REM   Phase 3: 25% - Frontend & Mobile
REM ============================================================

echo.
echo ============================================================
echo EMI LOCKER PHASED BUILDER
echo ============================================================
echo.
echo This will run TWO AI models together:
echo   - Guard Model: Reviews and plans (GPT-5-Nano)
echo   - Worker Model: Implements code (MiniMax-M2.7)
echo.
echo PHASES:
echo   Phase 1: 50%% - Core Architecture ^& Security
echo   Phase 2: 25%% - Backend ^& API
echo   Phase 3: 25%% - Frontend ^& Mobile
echo.
echo ============================================================
echo.

REM Check if PRD file exists
if not exist "EMI_Locker_PRD_Final.docx" (
    echo ERROR: PRD file not found: EMI_Locker_PRD_Final.docx
    echo Please make sure the PRD file is in this directory.
    pause
    exit /b 1
)

echo Choose run mode:
echo.
echo   1. Run ALL phases automatically (no verification)
echo   2. Run with verification after each phase (recommended)
echo   3. Run Phase 1 only (50%%)
echo   4. Resume from last checkpoint
echo   5. Exit
echo.

set /p choice="Enter choice (1-5): "

if "%choice%"=="1" goto :auto
if "%choice%"=="2" goto :interactive
if "%choice%"=="3" goto :phase1
if "%choice%"=="4" goto :resume
if "%choice%"=="5" goto :end

echo Invalid choice
pause
goto :end

:auto
echo.
echo Running ALL phases automatically...
echo.
python phased_builder.py --prd EMI_Locker_PRD_Final.docx --auto
goto :complete

:interactive
echo.
echo Running with verification after each phase...
echo.
python phased_builder.py --prd EMI_Locker_PRD_Final.docx
goto :complete

:phase1
echo.
echo Running Phase 1 only (50%%)...
echo.
python phased_builder.py --prd EMI_Locker_PRD_Final.docx --phase 1
goto :complete

:resume
echo.
echo Resuming from last checkpoint...
echo.
python phased_builder.py --prd EMI_Locker_PRD_Final.docx --resume
goto :complete

:complete
if %ERRORLEVEL% EQU 0 (
    echo.
    echo ============================================================
    echo BUILD PHASE COMPLETE
    echo ============================================================
    echo.
    echo Check these files:
    echo   - checkpoint.json (Current progress)
    echo   - implementation_plan.json (Guard's plan)
    echo   - build_log.md (Detailed logs)
    echo   - Generated code files
    echo.
) else (
    echo.
    echo ============================================================
    echo BUILD FAILED
    echo ============================================================
    echo.
    echo Check build_log.md for error details.
    echo.
)

:end
pause
