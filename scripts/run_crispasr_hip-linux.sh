#!/bin/bash
# CrispASR HIP/ROCm 运行脚本 - Linux/WSL2 版
# 专为 Vega 56/64 配置
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build-hip-linux"
BIN="$BUILD_DIR/bin/crispasr"

echo "========================================="
echo "CrispASR HIP/ROCm 启动器 (Linux/WSL2)"
echo "========================================="

# ----------------------------------------------------------
# 步骤 1: 检查二进制文件
# ----------------------------------------------------------
if [ ! -f "$BIN" ]; then
    echo "[ERROR] 找不到 $BIN"
    echo "请先运行 ./build-hip-linux.sh 编译"
    exit 1
fi

# ----------------------------------------------------------
# 步骤 2: 读取/设置显卡架构
# ----------------------------------------------------------
HSA_OVERRIDE="9.0.0"
GPU_TARGET="gfx900"

if [ -f "$BUILD_DIR/gpu_arch.txt" ]; then
    echo "[INFO] 从构建配置读取显卡架构..."
    HSA_OVERRIDE=$(sed -n '1p' "$BUILD_DIR/gpu_arch.txt")
    GPU_TARGET=$(sed -n '2p' "$BUILD_DIR/gpu_arch.txt")
else
    echo ""
    echo "[提示] 未找到构建配置，使用默认 Vega (gfx900)"
fi

echo "[INFO] HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE"
echo "[INFO] GPU_TARGET=$GPU_TARGET"

# ----------------------------------------------------------
# 步骤 3: 设置关键环境变量
# ----------------------------------------------------------
echo ""
echo "[INFO] 设置环境变量..."

# 架构欺骗（Vega需要，即使在Linux上有时也需要）
export HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE

# Vega/老卡关键：禁用SDMA防止模型加载挂起
export HSA_ENABLE_SDMA=0

# 禁用VMM（虚拟内存管理）提高老卡兼容性
export HSA_ENABLE_VMM=0

# 限制HSA可见设备（只使用第一个GPU）
export HIP_VISIBLE_DEVICES=0

# 日志级别
export AMD_LOG_LEVEL=3

# ----------------------------------------------------------
# 步骤 4: 检查ROCm是否能找到GPU
# ----------------------------------------------------------
echo ""
echo "[INFO] 检查GPU..."
if command -v rocminfo &> /dev/null; then
    echo "--- rocminfo 输出 (前20行) ---"
    rocminfo 2>&1 | head -30 || echo "[WARN] rocminfo 执行失败，继续尝试运行..."
    echo "--- rocminfo 结束 ---"
else
    echo "[WARN] rocminfo 未安装"
fi

# ----------------------------------------------------------
# 步骤 5: 解析参数
# ----------------------------------------------------------
MODEL=""
AUDIO=""

if [ $# -ge 2 ]; then
    MODEL="$1"
    AUDIO="$2"
    shift 2
else
    echo ""
    echo "用法: $0 <模型路径> <音频文件> [其他参数...]"
    echo ""
    echo "示例:"
    echo "  $0 models/sensevoice-small-q8_0.gguf samples/jfk.wav"
    echo "  $0 models/sensevoice-small-q8_0.gguf samples/paraformer_zh.wav -l zh"
    echo ""
    
    # 尝试自动查找模型和测试音频
    if [ -f "$SCRIPT_DIR/models/sensevoice-small-q8_0.gguf" ]; then
        MODEL="$SCRIPT_DIR/models/sensevoice-small-q8_0.gguf"
        echo "[INFO] 自动找到模型: $MODEL"
    fi
    
    if [ -f "$SCRIPT_DIR/samples/jfk.wav" ]; then
        AUDIO="$SCRIPT_DIR/samples/jfk.wav"
        echo "[INFO] 使用测试音频: $AUDIO"
    fi
fi

if [ -z "$MODEL" ] || [ -z "$AUDIO" ]; then
    echo "[ERROR] 请提供模型路径和音频文件"
    exit 1
fi

# ----------------------------------------------------------
# 步骤 6: 运行 CrispASR
# ----------------------------------------------------------
echo ""
echo "[INFO] 启动 CrispASR..."
echo "模型: $MODEL"
echo "音频: $AUDIO"
echo "额外参数: $*"
echo ""
echo "========================================="
echo ""

cd "$SCRIPT_DIR"
exec "$BIN" -m "$MODEL" -f "$AUDIO" "$@"
