# CrispASR HIP/ROCm Build Script - TheRock SDK (Vega 56/64 gfx900)
# 使用 TheRock ROCm SDK 的 hipcc 编译，原生支持 gfx900
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File build-hip-therock.ps1 -SourceDir "C:\path\to\crispasr" [-RocmPath "C:\path\to\therock"]
#
# Note: hipcc does NOT support paths with spaces. Mirror source to a space-free path first:
#   robocopy "C:\My Source" "C:\cabuild\repo" /MIR

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceDir,
    [string]$RocmPath = ""
)

$ErrorActionPreference = "Stop"

# ============================================================
# 路径配置 / Path Configuration
# ============================================================
$BUILD_DIR = "$SourceDir\build-hip-therock"
$OUT_DIR = "$SourceDir\bin-hip"

# TheRock ROCm SDK 路径 - auto-detect or use provided
if (-not $RocmPath) {
    $envRocm = $env:ROCM_PATH
    if ($envRocm -and (Test-Path "$envRocm\bin\hipcc.exe")) {
        $RocmPath = $envRocm
    } else {
        # Try common install location
        $defaultRocm = "$SourceDir\therock\venv\lib\site-packages\_rocm_sdk_devel"
        if (Test-Path "$defaultRocm\bin\hipcc.exe") {
            $RocmPath = $defaultRocm
        } else {
            Write-Host "[ERROR] TheRock ROCm SDK not found!"
            Write-Host "  Please specify with -RocmPath parameter"
            Write-Host "  Or set ROCM_PATH environment variable"
            Write-Host "  Or install in <source>\therock\venv\"
            exit 1
        }
    }
}
$ROCM_PATH = $RocmPath
$HIPCC = "$ROCM_PATH\bin\hipcc.exe"

Write-Host "============================================================"
Write-Host " CrispASR HIP Build - TheRock ROCm SDK (gfx900 Vega)"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# Step 1: 验证 TheRock ROCm SDK
# ============================================================
Write-Host "[1/6] Verifying TheRock ROCm SDK..."

if (-not (Test-Path $HIPCC)) {
    Write-Host "[ERROR] hipcc.exe not found at: $HIPCC"
    exit 1
}
Write-Host "  [OK] hipcc.exe found"

if (-not (Test-Path "$ROCM_PATH\bin\rocblas.dll")) {
    Write-Host "[ERROR] rocblas.dll not found!"
    exit 1
}
Write-Host "  [OK] rocblas.dll found"

if (-not (Test-Path "$ROCM_PATH\bin\hipblas.dll")) {
    Write-Host "[ERROR] hipblas.dll not found!"
    exit 1
}
Write-Host "  [OK] hipblas.dll found"

$gfx900Dir = "$ROCM_PATH\bin\rocblas\library\gfx900"
if (Test-Path $gfx900Dir) {
    $kernelCount = (Get-ChildItem $gfx900Dir).Count
    Write-Host "  [OK] gfx900 kernels: $kernelCount files"
} else {
    Write-Host "[ERROR] gfx900 kernel directory not found!"
    exit 1
}

# 显示 hipcc 版本
Write-Host ""
Write-Host "  hipcc version:"
& $HIPCC --version 2>&1 | ForEach-Object { Write-Host "    $_" }

# ============================================================
# Step 2: 设置 Vega 56/64 环境变量
# ============================================================
Write-Host ""
Write-Host "[2/6] Setting Vega environment variables..."

# Vega 56/64 = gfx900, HSA_OVERRIDE_GFX_VERSION=9.0.0
$env:HSA_OVERRIDE_GFX_VERSION = "9.0.0"
$env:HSA_ENABLE_SDMA = "0"           # 修复 Vega 模型加载挂起问题
$env:HIP_VISIBLE_DEVICES = "0"       # 使用第一个 GPU
$env:ROCM_PATH = $ROCM_PATH
$env:HIP_PATH = "$ROCM_PATH\bin"

# 将 ROCm bin 加入 PATH（运行时需要 DLL）
$env:PATH = "$ROCM_PATH\bin;" + $env:PATH

Write-Host "  HSA_OVERRIDE_GFX_VERSION = $($env:HSA_OVERRIDE_GFX_VERSION)"
Write-Host "  HSA_ENABLE_SDMA = $($env:HSA_ENABLE_SDMA)"
Write-Host "  ROCM_PATH = $($env:ROCM_PATH)"

# ============================================================
# Step 3: 加载 MSVC 编译环境
# ============================================================
Write-Host ""
Write-Host "[3/6] Loading MSVC build environment..."

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$VS_PATH = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
Write-Host "  VS Path: $VS_PATH"

$devShellModule = Join-Path $VS_PATH "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
Import-Module $devShellModule
Enter-VsDevShell -VsInstallPath $VS_PATH -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64"
Write-Host "  [OK] MSVC environment loaded"

# ============================================================
# Step 4: 检查构建工具 (Ninja 或 NMake)
# ============================================================
Write-Host ""
Write-Host "[4/6] Checking build tool..."

$ninjaPath = Get-Command ninja -ErrorAction SilentlyContinue
if ($ninjaPath) {
    $generator = "Ninja"
    $buildParallel = "-j $env:NUMBER_OF_PROCESSORS"
    Write-Host "  [OK] Using Ninja: $($ninjaPath.Source)"
} else {
    $generator = "NMake Makefiles"
    $buildParallel = ""
    Write-Host "  [OK] Using NMake (slower, no parallel)"
}

# ============================================================
# Step 5: 配置 CMake
# ============================================================
Write-Host ""
Write-Host "[5/6] Configuring CMake with HIP support..."

# 清理旧构建目录
if (Test-Path $BUILD_DIR) {
    Write-Host "  Cleaning old build directory..."
    Remove-Item $BUILD_DIR -Recurse -Force
}
New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null
New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null

# CMake 配置参数:
# - CMAKE_CXX_COMPILER = hipcc.exe (TheRock 的 HIP 编译器)
# - CMAKE_PREFIX_PATH = TheRock cmake 路径 (让 find_package 找到 hip/hipblas/rocblas)
# - GGML_HIP=ON: 启用 HIP 后端
# - AMDGPU_TARGETS=gfx900: Vega 56/64 架构
# - GGML_HIP_GRAPHS=OFF: 关闭 HIP Graphs (Vega 稳定性)
# - GGML_HIP_NO_VMM=ON: 禁用 VMM (防止 Vega VMM 问题)
# - GGML_HIP_ROCWMMA_FATTN=OFF: 关闭 rocWMMA (Vega 不支持)
# - GGML_HIP_MMQ_MFMA=OFF: 关闭 MFMA (Vega 不支持 MFMA 指令)

Push-Location $SourceDir
try {
    cmake -G $generator -B $BUILD_DIR `
        -DCMAKE_BUILD_TYPE=Release `
        -DCMAKE_C_COMPILER=$HIPCC `
        -DCMAKE_CXX_COMPILER=$HIPCC `
        -DCMAKE_PREFIX_PATH="$ROCM_PATH\lib\cmake;$ROCM_PATH\share\rocm\cmake" `
        -DROCM_PATH="$ROCM_PATH" `
        -DGGML_HIP=ON `
        -DGGML_HIP_GRAPHS=OFF `
        -DGGML_HIP_NO_VMM=ON `
        -DGGML_HIP_ROCWMMA_FATTN=OFF `
        -DGGML_HIP_MMQ_MFMA=OFF `
        -DGGML_CUDA=OFF `
        -DGGML_VULKAN=OFF `
        -DGGML_OPENCL=OFF `
        -DGGML_METAL=OFF `
        -DAMDGPU_TARGETS="gfx900" `
        -DGPU_TARGETS="gfx900" `
        -DCMAKE_HIP_ARCHITECTURES="gfx900" `
        -DGGML_LLAMAFILE_DEFAULT=ON `
        -DCRISPASR_BUILD_EXAMPLES=ON `
        -DCMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE=$OUT_DIR `
        -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=$OUT_DIR

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "[ERROR] CMake configuration failed!"
        Write-Host ""
        Write-Host "Troubleshooting:"
        Write-Host "  1. Check that TheRock ROCm SDK is properly installed"
        Write-Host "  2. Verify hipcc.exe is accessible"
        Write-Host "  3. Check CMake can find hip/hipblas/rocblas packages"
        exit 1
    }

    Write-Host "  [OK] CMake configuration complete"
    Write-Host ""

    # ============================================================
    # Step 6: 编译
    # ============================================================
    Write-Host "[6/6] Building CrispASR with HIP (gfx900 Vega)..."
    Write-Host "      This may take 10-30 minutes. Please be patient..."
    Write-Host ""

    cmake --build $BUILD_DIR --config Release $buildParallel

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "[ERROR] Build failed!"
        Write-Host ""
        Write-Host "Troubleshooting:"
        Write-Host "  1. If out of memory, reduce parallelism: change -j to -j 4 or -j 2"
        Write-Host "  2. Ensure HSA_OVERRIDE_GFX_VERSION=9.0.0 is set"
        Write-Host "  3. Check TheRock ROCm SDK installation"
        exit 1
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host " BUILD SUCCESS! - Vega 56/64 HIP (gfx900)"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host "Output directory: $OUT_DIR"
    Write-Host ""
    Write-Host "Built executables:"
    Get-ChildItem $OUT_DIR -Filter "*.exe" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  $($_.Name) ($([math]::Round($_.Length/1MB, 1)) MB)"
    }

    # 检查关键 DLL 是否已复制到输出目录
    Write-Host ""
    Write-Host "Checking runtime DLLs..."
    $runtimeDlls = @("amdhip64_7.dll", "rocblas.dll", "hipblas.dll")
    foreach ($dll in $runtimeDlls) {
        $srcDll = "$ROCM_PATH\bin\$dll"
        $dstDll = "$OUT_DIR\$dll"
        if (Test-Path $srcDll) {
            if (-not (Test-Path $dstDll)) {
                Copy-Item $srcDll $dstDll -Force
                Write-Host "  Copied: $dll"
            } else {
                Write-Host "  [OK] $dll already present"
            }
        }
    }

    # 复制 rocblas library 目录 (gfx900 kernels)
    $rocblasLibSrc = "$ROCM_PATH\bin\rocblas"
    $rocblasLibDst = "$OUT_DIR\rocblas"
    if ((Test-Path $rocblasLibSrc) -and -not (Test-Path $rocblasLibDst)) {
        Write-Host "  Copying rocblas library (gfx900 kernels)..."
        Copy-Item $rocblasLibSrc $rocblasLibDst -Recurse -Force
        Write-Host "  [OK] rocblas library copied"
    }

    Write-Host ""
    Write-Host "To run CrispASR with HIP:"
    Write-Host "  set HSA_OVERRIDE_GFX_VERSION=9.0.0"
    Write-Host "  set HSA_ENABLE_SDMA=0"
    Write-Host "  $OUT_DIR\crispasr-cli.exe -m <model.gguf> -f <audio.wav>"
    Write-Host ""

} finally {
    Pop-Location
}
