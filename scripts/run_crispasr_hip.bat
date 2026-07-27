@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: CrispASR HIP/ROCm 运行脚本 - Windows 版 (Vega 56/64 专用)
:: 自动设置所有必要环境变量
::
:: Usage:
::   run_crispasr_hip.bat [crispasr_dir] [model] [audio] [extra args...]
::   If crispasr_dir not provided, searches current dir and parent
:: ============================================================

echo ============================================================
echo  CrispASR HIP/ROCm 启动器 (Windows Vega 专用)
echo ============================================================
echo.

:: Accept optional first arg as CrispASR directory
if not "%~1"=="" (
    if exist "%~1\bin-hip\crispasr.exe" (
        set "CRISPASR_DIR=%~1"
        shift
    ) else if exist "%~1\crispasr.exe" (
        set "CRISPASR_DIR=%~dp0"
        set "BIN=%~1\crispasr.exe"
        shift
    )
)

:: Auto-detect CrispASR directory if not set
if not defined CRISPASR_DIR (
    :: Try current directory
    if exist "%CD%\bin-hip\crispasr.exe" (
        set "CRISPASR_DIR=%CD%"
    ) else if exist "%CD%\crispasr.exe" (
        set "CRISPASR_DIR=%CD%"
        set "BIN=%CD%\crispasr.exe"
    ) else (
        :: Try parent of scripts directory
        for %%I in ("%~dp0..") do set "CRISPASR_DIR=%%~fI"
    )
)

if not defined BIN set "BIN=%CRISPASR_DIR%\bin-hip\crispasr.exe"

:: ----------------------------------------------------------
:: 步骤 1: 检查二进制文件
:: ----------------------------------------------------------
if not exist "%BIN%" (
    echo [ERROR] 找不到 %BIN%
    echo.
    echo 请先运行 build-hip.bat 编译
    pause
    exit /b 1
)

:: ----------------------------------------------------------
:: 步骤 2: 读取/设置显卡架构配置
:: ----------------------------------------------------------
set "HSA_OVERRIDE=9.0.0"
set "GPU_TARGET=gfx900"
set "ROCM_PATH=C:\hip"

if exist "%BUILD_DIR%\gpu_arch.txt" (
    echo [INFO] 从构建配置读取显卡架构...
    set /p HSA_OVERRIDE=<"%BUILD_DIR%\gpu_arch.txt"
    set SKIP_FIRST=1
    for /f "usebackq delims=" %%a in ("%BUILD_DIR%\gpu_arch.txt") do (
        if defined SKIP_FIRST (
            set SKIP_FIRST=
        ) else (
            if not defined GPU_TARGET_READ (
                set GPU_TARGET=%%a
                set GPU_TARGET_READ=1
            ) else (
                set ROCM_PATH=%%a
            )
        )
    )
) else (
    echo.
    echo [提示] 未找到构建配置，使用默认 Vega (gfx900)
)

echo [INFO] HSA_OVERRIDE_GFX_VERSION=%HSA_OVERRIDE%
echo [INFO] GPU_TARGET=%GPU_TARGET%
echo [INFO] ROCM_PATH=%ROCM_PATH%

:: ----------------------------------------------------------
:: 步骤 3: 添加 ROCm 到 PATH
:: ----------------------------------------------------------
if exist "%ROCM_PATH%\bin" (
    set "PATH=%ROCM_PATH%\bin;%PATH%"
    echo [OK] 已添加 ROCm/bin 到 PATH
) else (
    echo [WARN] ROCm 路径 %ROCM_PATH%\bin 不存在
)

:: ----------------------------------------------------------
:: 步骤 4: 设置 Vega 专用环境变量 (关键!)
:: ----------------------------------------------------------
echo.
echo [INFO] 设置 Vega 专用环境变量...

:: [必须] 架构欺骗 - 让ROCm以为我们是官方支持的卡
set "HSA_OVERRIDE_GFX_VERSION=%HSA_OVERRIDE%"

:: [必须] 禁用SDMA引擎 - 防止Vega加载模型时挂起
set "HSA_ENABLE_SDMA=0"

:: [推荐] 禁用虚拟内存管理 - 提高Vega稳定性
set "HSA_ENABLE_VMM=0"

:: [推荐] 只使用第一个GPU
set "HIP_VISIBLE_DEVICES=0"

:: [可选] 日志级别 (3=详细，排错时用；0=静默)
set "AMD_LOG_LEVEL=2"

:: [可选] 禁用GPU超时检测
set "GPU_MAX_HW_QUEUES=4"
set "HSA_ENABLE_SDMA_WAIT_SUBMIT=0"

:: ----------------------------------------------------------
:: 步骤 5: 检查rocblas.dll (Vega关键)
:: ----------------------------------------------------------
echo.
echo [INFO] 检查 rocblas.dll...
if exist "%ROCM_PATH%\bin\rocblas.dll" (
    echo [OK] rocblas.dll 已找到
    echo.
    echo [提醒] Vega 用户请确认您已替换 rocblas.dll 为支持 gfx900 的版本!
    echo        如果运行时出现 "hipErrorNoBinaryForGpu" 错误，说明需要替换。
) else (
    echo [WARN] rocblas.dll 未找到，程序可能无法启动
)

:: ----------------------------------------------------------
:: 步骤 6: 解析命令行参数
:: ----------------------------------------------------------
set "MODEL="
set "AUDIO="

if "%~1"=="" (
    echo.
    echo 用法: %~nx0 [模型路径] [音频文件] [其他参数...]
    echo.
    echo 示例:
    echo   %~nx0 models\sensevoice-small-q8_0.gguf samples\jfk.wav
    echo   %~nx0 models\sensevoice-small-q8_0.gguf samples\paraformer_zh.wav -l zh
    echo.
    
    :: 尝试自动查找模型
    if exist "%CRISPASR_DIR%models\sensevoice-small-q8_0.gguf" (
        set "MODEL=%CRISPASR_DIR%models\sensevoice-small-q8_0.gguf"
        echo [INFO] 自动找到模型: !MODEL!
    )
    
    :: 尝试查找测试音频
    if exist "%CRISPASR_DIR%samples\jfk.wav" (
        set "AUDIO=%CRISPASR_DIR%samples\jfk.wav"
        echo [INFO] 使用测试音频: !AUDIO!
    )
) else (
    set "MODEL=%~1"
    set "AUDIO=%~2"
    shift
    shift
)

if "%MODEL%"=="" (
    echo.
    set /p MODEL="请输入模型路径: "
)
if "%AUDIO%"=="" (
    set /p AUDIO="请输入音频文件路径: "
)

if not exist "%MODEL%" (
    echo [ERROR] 模型文件不存在: %MODEL%
    pause
    exit /b 1
)
if not exist "%AUDIO%" (
    echo [ERROR] 音频文件不存在: %AUDIO%
    pause
    exit /b 1
)

:: ----------------------------------------------------------
:: 步骤 7: 运行 CrispASR
:: ----------------------------------------------------------
echo.
echo ============================================================
echo [INFO] 启动 CrispASR (HIP 加速)...
echo ============================================================
echo 模型: %MODEL%
echo 音频: %AUDIO%
echo.

cd /d "%CRISPASR_DIR%"
"%BIN%" -m "%MODEL%" -f "%AUDIO%" %*

echo.
echo ============================================================
if %ERRORLEVEL% equ 0 (
    echo [完成] CrispASR 执行成功
) else (
    echo [错误] CrispASR 执行失败 (错误码: %ERRORLEVEL%)
    echo.
    echo 如果出现 "hipErrorNoBinaryForGpu" 错误:
    echo   1. 确认 HSA_OVERRIDE_GFX_VERSION=%HSA_OVERRIDE% 已设置
    echo   2. 需要替换 rocblas.dll 为支持 gfx900 的社区版本
    echo   3. 下载地址见 build-hip.bat 编译后的提示
    echo.
    echo 如果程序启动后卡住不动:
    echo   1. 确认设置了 HSA_ENABLE_SDMA=0 (本脚本已设置)
    echo   2. 尝试降低模型大小或使用更小的量化版本
)
echo ============================================================
echo.

pause

