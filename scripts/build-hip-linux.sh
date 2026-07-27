#!/bin/bash
# CrispASR HIP/ROCm 构建脚本 - Linux/WSL2 版
# 专为老AMD显卡 (Polaris/Vega/Navi10) 设计
# Vega 56/64 使用 gfx900
set -e

echo "========================================="
echo "CrispASR HIP/ROCm 构建脚本 (Linux/WSL2)"
echo "========================================="

# ----------------------------------------------------------
# 步骤 1: 检测/选择显卡架构
# ----------------------------------------------------------
echo ""
echo "[1/5] 选择显卡架构:"
echo "  [1] Polaris  (RX 470/480/570/580/590) - gfx803"
echo "  [2] Vega     (Vega 56/64/Vega 7/APU)   - gfx900  (默认)"
echo "  [3] Navi 10  (RX 5700/5700 XT)         - gfx1010"
echo ""

if [ -z "$GPU_ARCH_CHOICE" ]; then
    read -p "请输入选项 [1-3, 默认: 2]: " GPU_ARCH_CHOICE
fi

GPU_ARCH_CHOICE=${GPU_ARCH_CHOICE:-2}

case $GPU_ARCH_CHOICE in
    1)
        GPU_TARGET="gfx803"
        HSA_OVERRIDE="8.0.3"
        ;;
    2)
        GPU_TARGET="gfx900"
        HSA_OVERRIDE="9.0.0"
        ;;
    3)
        GPU_TARGET="gfx1010"
        HSA_OVERRIDE="10.1.0"
        ;;
    *)
        echo "[ERROR] 无效选项"
        exit 1
        ;;
esac

echo "[INFO] 目标架构: $GPU_TARGET"
echo "[INFO] HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE"

# ----------------------------------------------------------
# 步骤 2: 检查依赖
# ----------------------------------------------------------
echo ""
echo "[2/5] 检查构建依赖..."

MISSING_DEPS=()

if ! command -v cmake &> /dev/null; then
    MISSING_DEPS+=("cmake")
fi

if ! command -v hipcc &> /dev/null; then
    MISSING_DEPS+=("hipcc")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "[ERROR] 缺少依赖: ${MISSING_DEPS[*]}"
    echo ""
    echo "Ubuntu/Debian 安装命令:"
    echo "  sudo apt update && sudo apt install -y build-essential cmake git hipcc libhipblas-dev librocblas-dev rocminfo"
    echo ""
    exit 1
fi

echo "[OK] 依赖检查通过"
echo "  hipcc: $(which hipcc)"
echo "  cmake: $(cmake --version | head -1)"

# ----------------------------------------------------------
# 步骤 3: 添加用户到渲染组（如果需要）
# ----------------------------------------------------------
echo ""
echo "[3/5] 检查用户组权限..."

if ! groups | grep -q render; then
    echo "[WARN] 当前用户不在 render 组"
    echo "运行: sudo usermod -aG video,render \$USER"
    echo "然后注销并重新登录"
fi

if ! groups | grep -q video; then
    echo "[WARN] 当前用户不在 video 组"
fi

# ----------------------------------------------------------
# 步骤 4: 配置 CMake
# ----------------------------------------------------------
echo ""
echo "[4/5] 配置 CMake..."

BUILD_DIR="build-hip-linux"
rm -rf $BUILD_DIR

# 关键 CMake 参数:
# -DGGML_HIP=ON: 启用 HIP 后端
# -DGGML_VULKAN=OFF: 禁用 Vulkan
# -DGGML_CUDA=OFF: 禁用 CUDA
# -DCMAKE_HIP_ARCHITECTURES=$GPU_TARGET: 指定目标架构
# -DAMDGPU_TARGETS=$GPU_TARGET: AMDGPU 目标
# -DCMAKE_BUILD_TYPE=Release: 发布模式优化
# -DGGML_HIP_NO_VMM=ON: 禁用VMM（老卡兼容性更好）
# 注意: 不要设置 HIPCXX 环境变量，让 CMake 自动检测 clang
# Ubuntu 26.04 的 hipcc 是 wrapper，CMake 4.x 不接受它作为 HIPCXX

cmake -B $BUILD_DIR \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_HIP=ON \
    -DGGML_CUDA=OFF \
    -DGGML_VULKAN=OFF \
    -DCMAKE_HIP_ARCHITECTURES=$GPU_TARGET \
    -DAMDGPU_TARGETS=$GPU_TARGET \
    -DGPU_TARGETS=$GPU_TARGET \
    -DGGML_HIP_NO_VMM=ON \
    -DGGML_HIP_GRAPHS=OFF \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DCMAKE_HIP_COMPILER=clang++-21 \
    "$@"

if [ $? -ne 0 ]; then
    echo "[ERROR] CMake 配置失败"
    exit 1
fi

# 保存架构配置到文件
echo "$HSA_OVERRIDE" > $BUILD_DIR/gpu_arch.txt
echo "$GPU_TARGET" >> $BUILD_DIR/gpu_arch.txt

# ----------------------------------------------------------
# 步骤 5: 编译
# ----------------------------------------------------------
echo ""
echo "[5/5] 开始编译 (使用 $(nproc) 个核心)..."
echo "这可能需要 5-15 分钟，请耐心等待..."
echo ""

cmake --build $BUILD_DIR --config Release -j$(nproc) --target crispasr-cli

if [ $? -ne 0 ]; then
    echo "[ERROR] 编译失败"
    exit 1
fi

echo ""
echo "========================================="
echo "[SUCCESS] 编译完成!"
echo "========================================="
echo ""
echo "二进制位置: $BUILD_DIR/bin/crispasr"
echo ""
echo "运行方式:"
echo "  export HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE"
echo "  export HSA_ENABLE_SDMA=0  # Vega 可能需要这个防止加载挂起"
echo "  $BUILD_DIR/bin/crispasr -m models/sensevoice-small-q8_0.gguf samples/jfk.wav"
echo ""
echo "或者使用提供的运行脚本: ./run_crispasr_hip.sh"
echo ""
