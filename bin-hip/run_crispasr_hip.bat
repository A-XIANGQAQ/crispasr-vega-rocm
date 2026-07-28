@echo off
REM ============================================================
REM CrispASR HIP Run Script for AMD Vega 56/64 (gfx900)
REM Uses TheRock ROCm SDK with HSA_OVERRIDE_GFX_VERSION=9.0.0
REM ============================================================

REM --- Set ROCm path (TheRock SDK installation) ---
set ROCM_PATH=G:\daily agent\CrispASR\therock\venv\lib\site-packages\_rocm_sdk_devel
set HIP_PATH=%ROCM_PATH%\bin

REM --- Vega 56/64 specific environment variables ---
set HSA_OVERRIDE_GFX_VERSION=9.0.0
set HSA_ENABLE_SDMA=0
set HIP_VISIBLE_DEVICES=0

REM --- Model cache on G drive (NOT C drive) ---
set CRISPASR_CACHE_DIR=G:\daily agent\CrispASR\models

REM --- Add ROCm bin to PATH ---
set PATH=%HIP_PATH%;%PATH%

REM --- Set library search path ---
set LIB=%ROCM_PATH%\lib;%LIB%

REM --- Set binary directory ---
set BIN_DIR=%~dp0

REM --- Show banner ---
echo ============================================================
echo  CrispASR HIP - AMD Vega 56/64 (gfx900)
echo ============================================================
echo  ROCm Path: %ROCM_PATH%
echo  HSA_OVERRIDE_GFX_VERSION: %HSA_OVERRIDE_GFX_VERSION%
echo  HSA_ENABLE_SDMA: %HSA_ENABLE_SDMA%
echo  Binary: %BIN_DIR%crispasr.exe
echo ============================================================
echo.

REM --- Run crispasr with all passed arguments ---
"%BIN_DIR%crispasr.exe" %*

REM --- Exit with crispasr's exit code ---
exit /b %ERRORLEVEL%
