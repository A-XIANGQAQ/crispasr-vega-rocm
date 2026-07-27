@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: CrispASR HIP/ROCm 构建脚本 - Windows 版 (Vega 56/64 专用)
:: 彻底重构版 - 专为老AMD显卡优化
:: ============================================================

echo ============================================================
echo  CrispASR HIP/ROCm 加速构建脚本 (Windows Vega 专用)
echo ============================================================
echo.

:: ----------------------------------------------------------
:: 步骤 1: 检查 ROCm/HIP SDK 安装
:: ----------------------------------------------------------
echo [1/7] 检查 HIP SDK 环境...

set "HIP_SDK_PATHS=C:\hip;C:\Program Files\AMD\ROCm\5.7;C:\Program Files\AMD\ROCm\6.0;C:\Program Files\AMD\ROCm\6.1;C:\Program Files\AMD\ROCm\6.2;C:\Program Files\AMD\ROCm;C:\Program Files\AMD\HIP"
set "HIP_PATH="
set "ROCM_PATH="

for %%p in (%HIP_SDK_PATHS:;= %) do (
    if exist "%%p\bin\hipcc.bat" (
        set "ROCM_PATH=%%p"
        set "HIP_PATH=%%p\bin"
    )
)

if defined ROCM_PATH (
    echo [OK] 找到 HIP SDK: !ROCM_PATH!
) else (
    echo [ERROR] 未找到 HIP SDK!
    echo.
    echo ============================================================
    echo  请先安装 AMD HIP SDK for Windows (Vega 用户必读!)
    echo ============================================================
    echo.
    echo  [Vega 56/64 强烈推荐 HIP SDK 5.7.1]
    echo  ROCm 5.7 是最后一个原生包含 gfx900 (Vega) 内核的版本!
    echo  6.x 版本已移除 Vega 支持，需要额外替换 rocblas.dll
    echo.
    echo  官方下载页面:
    echo    https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html
    echo.
    echo  历史版本下载 (5.7.1 推荐):
    echo    在 AMD 官网页面底部找 "HIP SDK 5.7.1 for Windows 10/11"
    echo.
    echo  安装说明:
    echo    1. 下载 HIP SDK 5.7.1 (约 1.5GB)
    echo    2. 以管理员身份运行安装程序
    echo    3. 建议安装到默认路径 C:\hip 或 C:\Program Files\AMD\ROCm\5.7
    echo    4. 安装时可取消勾选 "Visual Studio Integration" 节省空间
    echo    5. 安装完成后重启电脑
    echo    6. 不需要卸载现有 Adrenalin 驱动 (HIP SDK 会兼容)
    echo.
    echo  Vega 用户 rocBLAS 注意事项:
    echo    - HIP SDK 5.7.1 自带的 rocblas.dll 可能已包含 gfx900 支持
    echo    - 如果运行时出现 "hipErrorNoBinaryForGpu":
    echo      1. 下载老卡专用 rocBLAS: https://www.mediafire.com/file/boobrm5vjg7ev50/rocBLAS-HIP5.7.1-win%%2528old_gpu%%2529.rar/file
    echo      2. 备份并替换 ROCm\bin\rocblas.dll 和 ROCm\bin\rocblas\ 文件夹
    echo.
    pause
    exit /b 1
)

:: 添加 HIP 到 PATH
set "PATH=!HIP_PATH!;%PATH%"

:: ----------------------------------------------------------
:: 步骤 2: 选择显卡架构
:: ----------------------------------------------------------
echo.
echo [2/7] 选择显卡架构:
echo   [1] Polaris  (RX 470/480/570/580/590) - gfx803
echo   [2] Vega     (Vega 56/64/Vega 7/APU)   - gfx900  [默认]
echo   [3] Navi 10  (RX 5700/5700 XT)         - gfx1010
echo.
set /p GPU_ARCH_CHOICE="请输入选项 [1-3, 默认: 2]: "

if "%GPU_ARCH_CHOICE%"=="" set "GPU_ARCH_CHOICE=2"

if "%GPU_ARCH_CHOICE%"=="1" (
    set "GPU_TARGET=gfx803"
    set "HSA_OVERRIDE=8.0.3"
)
if "%GPU_ARCH_CHOICE%"=="2" (
    set "GPU_TARGET=gfx900"
    set "HSA_OVERRIDE=9.0.0"
)
if "%GPU_ARCH_CHOICE%"=="3" (
    set "GPU_TARGET=gfx1010"
    set "HSA_OVERRIDE=10.1.0"
)

if not "%GPU_ARCH_CHOICE%"=="1" if not "%GPU_ARCH_CHOICE%"=="2" if not "%GPU_ARCH_CHOICE%"=="3" (
    echo [ERROR] 无效选项
    pause
    exit /b 1
)

echo [OK] 目标架构: %GPU_TARGET% (HSA_OVERRIDE_GFX_VERSION=%HSA_OVERRIDE%)

:: ----------------------------------------------------------
:: 步骤 3: 查找 Visual Studio
:: ----------------------------------------------------------
echo.
echo [3/7] 检查 Visual Studio 构建工具...

set "vswhere=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "!vswhere!" (
    echo [ERROR] vswhere.exe not found. 请安装 Visual Studio 2022 Build Tools (含 C++ 桌面开发)。
    echo 下载地址: https://visualstudio.microsoft.com/visual-cpp-build-tools/
    pause
    exit /b 1
)

for /f "usebackq tokens=*" %%i in (`"!vswhere!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
    set "vs_path=%%i"
)

if not defined vs_path (
    echo [ERROR] 未找到 Visual Studio C++ 构建工具。
    pause
    exit /b 1
)

echo [OK] Visual Studio 路径: !vs_path!

:: 初始化 MSVC 环境
set "vcvars=!vs_path!\VC\Auxiliary\Build\vcvars64.bat"
if not exist "!vcvars!" (
    echo [ERROR] vcvars64.bat not found at !vcvars!
    pause
    exit /b 1
)

echo [INFO] 初始化 MSVC 编译环境...
call "!vcvars!"

:: ----------------------------------------------------------
:: 步骤 4: 检查 Ninja
:: ----------------------------------------------------------
echo.
echo [4/7] 检查构建工具...

where ninja >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [WARN] Ninja 未找到，使用 NMake (编译会慢一些)
    set "CMAKE_GENERATOR=NMake Makefiles"
    set "BUILD_PARALLEL="
) else (
    echo [OK] Ninja 已找到
    set "CMAKE_GENERATOR=Ninja"
    set "BUILD_PARALLEL=-j %NUMBER_OF_PROCESSORS%"
)

:: ----------------------------------------------------------
:: 步骤 5: 配置 CMake (Vega 专用优化)
:: ----------------------------------------------------------
echo.
echo [5/7] 配置 CMake (gfx900 Vega 专用优化)...

set "BUILD_DIR=build-hip"

if exist "%BUILD_DIR%" (
    echo [INFO] 清理旧的构建目录...
    rmdir /s /q "%BUILD_DIR%"
)

:: Vega 专用 CMake 参数:
:: -DGGML_HIP=ON: 启用 HIP 后端
:: -DGGML_HIP_GRAPHS=OFF: 关闭HIP Graphs (老卡稳定性)
:: -DGGML_HIP_NO_VMM=ON: 禁用VMM (防止Vega上的VMM问题)
:: -DCMAKE_HIP_ARCHITECTURES=gfx900: 明确指定目标架构
:: -DGGML_BLAS=ON: 使用hipBLAS
:: -DCMAKE_BUILD_TYPE=Release: 最大优化

cmake -G "%CMAKE_GENERATOR%" -B "%BUILD_DIR%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_C_COMPILER="!HIP_PATH!\hipcc.bat" ^
    -DCMAKE_CXX_COMPILER="!HIP_PATH!\hipcc.bat" ^
    -DGGML_HIP=ON ^
    -DGGML_HIP_GRAPHS=OFF ^
    -DGGML_HIP_NO_VMM=ON ^
    -DGGML_CUDA=OFF ^
    -DGGML_VULKAN=OFF ^
    -DGGML_BLAS=ON ^
    -DGGML_BLAS_VENDOR=hipblas ^
    -DAMDGPU_TARGETS=%GPU_TARGET% ^
    -DGPU_TARGETS=%GPU_TARGET% ^
    -DCMAKE_HIP_ARCHITECTURES=%GPU_TARGET% ^
    -DGGML_LLAMAFILE_DEFAULT=ON ^
    -DCRISPASR_BUILD_EXAMPLES=ON ^
    %*

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] CMake 配置失败!
    echo.
    echo 常见问题排查:
    echo   1. 确认 HIP SDK 已完整安装 (包含 hipcc, hipblas, rocblas)
    echo   2. 尝试使用 ROCm 6.0.x 版本 (对 Vega 兼容性最好)
    echo   3. 如果编译器错误，尝试安装 Visual Studio 2022 17.8 或更新版本
    pause
    exit /b 1
)

echo [OK] CMake 配置完成

:: ----------------------------------------------------------
:: 步骤 6: 编译
:: ----------------------------------------------------------
echo.
echo [6/7] 开始编译 CrispASR (HIP 加速版)...
echo       目标架构: %GPU_TARGET% (Vega 56/64)
echo       这可能需要 10-20 分钟，请耐心等待...
echo.

cmake --build "%BUILD_DIR%" --target crispasr-cli %BUILD_PARALLEL%

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] 编译失败!
    echo.
    echo 排错建议:
    echo   1. 如果内存不足，降低并行度: 修改 -j 参数为 -j 4 或 -j 2
    echo   2. 确认使用的是 HIP SDK 而不是仅 Adrenalin 驱动
    echo   3. Vega 用户请确认 HSA_OVERRIDE_GFX_VERSION=9.0.0
    pause
    exit /b 1
)

:: ----------------------------------------------------------
:: 步骤 7: 验证输出和后处理
:: ----------------------------------------------------------
echo.
echo [7/7] 验证构建产物...

if not exist "%BUILD_DIR%\bin\crispasr.exe" (
    echo [ERROR] 编译成功但未找到 crispasr.exe
    dir /s /b "%BUILD_DIR%\*.exe"
    pause
    exit /b 1
)

:: 保存架构配置供运行脚本使用
echo %HSA_OVERRIDE%> "%BUILD_DIR%\gpu_arch.txt"
echo %GPU_TARGET%>> "%BUILD_DIR%\gpu_arch.txt"
echo %ROCM_PATH%>> "%BUILD_DIR%\gpu_arch.txt"

echo [OK] 编译成功!
echo.
echo ============================================================
echo  构建完成! - Vega 56/64 HIP 加速版
echo ============================================================
echo.
echo 可执行文件位置: %CD%\%BUILD_DIR%\bin\crispasr.exe
echo.
echo ============================================================
echo  Vega 重要: 运行前请确认 rocblas.dll 包含 gfx900 内核!
echo ============================================================
echo.
echo HIP SDK 5.7.1 自带的 rocblas.dll 通常已包含 gfx900 支持。
echo 如果运行时出现 "hipErrorNoBinaryForGpu" 错误，需要替换:
echo.
echo 老卡专用 rocBLAS 下载地址 (HIP 5.7.1):
echo   https://www.mediafire.com/file/boobrm5vjg7ev50/rocBLAS-HIP5.7.1-win%%2528old_gpu%%2529.rar/file
echo.
echo 替换步骤:
echo   1. 备份原文件:
echo      copy "!ROCM_PATH!\bin\rocblas.dll" "!ROCM_PATH!\bin\rocblas.dll.bak"
echo      xcopy /e /i "!ROCM_PATH!\bin\rocblas" "!ROCM_PATH!\bin\rocblas.bak\"
echo   2. 解压下载的 rar 文件
echo   3. 替换 rocblas.dll 和 rocblas\ 文件夹到 "!ROCM_PATH!\bin\"
echo.
echo 运行方式:
echo   1. 使用 run_crispasr_hip.bat 脚本启动 (自动设置环境变量)
echo   2. 或手动设置环境变量后运行:
echo      set HSA_OVERRIDE_GFX_VERSION=%HSA_OVERRIDE%
echo      set HSA_ENABLE_SDMA=0
echo      set HIP_VISIBLE_DEVICES=0
echo      %BUILD_DIR%\bin\crispasr.exe -m models\sensevoice-small-q8_0.gguf -f samples\jfk.wav
echo.
echo 关键环境变量说明:
echo   HSA_OVERRIDE_GFX_VERSION=%HSA_OVERRIDE%  - 架构欺骗，必须设置!
echo   HSA_ENABLE_SDMA=0          - 防止 Vega 加载模型时挂起
echo   AMD_LOG_LEVEL=3            - 显示详细GPU日志用于排错
echo.

pause
