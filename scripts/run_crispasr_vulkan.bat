@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: CrispASR Vulkan 加速运行脚本 (兼容性最好的 GPU 加速方案)
:: 适用于: 所有支持 Vulkan 1.1+ 的 AMD/NVIDIA/Intel 显卡
:: ============================================================

echo ============================================================
echo  CrispASR Vulkan 加速版 - 语音识别启动脚本
echo ============================================================
echo.

:: ----------------------------------------------------------
:: 配置区域
:: ----------------------------------------------------------
set "BUILD_DIR=build-vulkan"
set "DEFAULT_MODEL=..\models\sensevoice-small-q8_0.gguf"
set "DEFAULT_AUDIO="

:: ----------------------------------------------------------
:: 检查可执行文件
:: ----------------------------------------------------------
set "EXE_PATH=%BUILD_DIR%\bin\crispasr.exe"

if not exist "%EXE_PATH%" (
    echo [ERROR] 未找到 Vulkan 版 CrispASR!
    echo.
    echo 请先运行 build-vulkan.bat 完成编译。
    echo Vulkan 后端优势:
    echo   - 兼容性最好，无需修改驱动
    echo   - 支持所有 AMD/NVIDIA/Intel 显卡
    echo   - 官方 Adrenalin 驱动即可运行
    echo.
    pause
    exit /b 1
)

echo [OK] 找到 Vulkan 版 CrispASR
echo.

:: ----------------------------------------------------------
:: 设置 Vulkan 环境变量 (可选)
:: ----------------------------------------------------------

:: 指定使用第 1 块独立显卡 (0=第一块, 1=第二块)
set "GGML_VK_VISIBLE_DEVICES=0"

:: 可选: 限制显存使用 (MB)
:: set "GGML_VK_MAX_GPU_MEM=7000"

:: ----------------------------------------------------------
:: 解析参数
:: ----------------------------------------------------------
set "MODEL_PATH=%~1"
if "%MODEL_PATH%"=="" set "MODEL_PATH=%DEFAULT_MODEL%"

if not exist "%MODEL_PATH%" (
    echo [ERROR] 模型文件不存在: %MODEL_PATH%
    echo.
    echo 请将 GGUF 模型放在 models 目录，或通过参数指定:
    echo   run_crispasr_vulkan.bat [模型路径] [音频文件]
    echo.
    pause
    exit /b 1
)

echo [OK] 模型: %MODEL_PATH%

set "AUDIO_PATH=%~2"
if "%AUDIO_PATH%"=="" (
    if not "%DEFAULT_AUDIO%"=="" (
        set "AUDIO_PATH=%DEFAULT_AUDIO%"
    ) else (
        echo.
        echo 用法: run_crispasr_vulkan.bat [模型路径] [音频文件]
        echo.
        echo 示例:
        echo   run_crispasr_vulkan.bat
        echo   run_crispasr_vulkan.bat ..\models\sensevoice-small-q8_0.gguf ..\cv_cheerful.wav
        echo.
        set /p AUDIO_PATH="请输入音频文件路径: "
    )
)

if not exist "%AUDIO_PATH%" (
    echo [ERROR] 音频文件不存在: %AUDIO_PATH%
    pause
    exit /b 1
)

echo [OK] 音频: %AUDIO_PATH%
echo.

:: ----------------------------------------------------------
:: 运行 CrispASR
:: ----------------------------------------------------------
echo ============================================================
echo  开始语音识别 (Vulkan 加速)...
echo ============================================================
echo.

"%EXE_PATH%" ^
    -m "%MODEL_PATH%" ^
    -f "%AUDIO_PATH%" ^
    -ngl 99 ^
    -l auto ^
    -t 4 ^
    %*

set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo ============================================================
if %EXIT_CODE% equ 0 (
    echo  识别完成!
) else (
    echo  运行出错 (退出码: %EXIT_CODE%)
    echo.
    echo 如果遇到显存不足:
    echo   1. 降低 -ngl 参数 (如 -ngl 20)
    echo   2. 设置 GGML_VK_MAX_GPU_MEM 限制显存使用
)
echo ============================================================
echo.

pause
exit /b %EXIT_CODE%
