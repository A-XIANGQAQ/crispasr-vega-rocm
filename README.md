# CrispASR on AMD Vega 56/64 with ROCm/HIP

> 在 AMD Vega 56/64 显卡上通过 ROCm/HIP 实现 CrispASR GPU 加速的完整方案。
> 不需要 WSL，不需要 Linux，纯 Windows 原生运行。
>
> A complete solution for running CrispASR with GPU acceleration via ROCm/HIP on AMD Vega 56/64 GPUs.
> No WSL, no Linux — pure Windows native.

![Platform](https://img.shields.io/badge/platform-Windows-blue)
![GPU](https://img.shields.io/badge/GPU-AMD%20Vega%20gfx900-red)
![Backend](https://img.shields.io/badge/backend-ROCm%2FHIP-orange)
![ROCm](https://img.shields.io/badge/ROCm-5.7.1-green)
![License](https://img.shields.io/badge/license-MIT%2FApache-lightgrey)

## 目录 / Table of Contents

- [功能 / Features](#功能--features)
- [测试环境 / Test Environment](#测试环境--test-environment)
- [性能实测 / Performance Benchmarks](#性能实测--performance-benchmarks)
- [快速上手 / Quick Start](#快速上手--quick-start)
- [脚本说明 / Scripts](#脚本说明--scripts)
- [关键技术要点 / Key Technical Points](#关键技术要点--key-technical-points)
- [踩坑清单 / Common Pitfalls](#踩坑清单--common-pitfalls)
- [适用显卡 / Supported GPUs](#适用显卡--supported-gpus)
- [折腾历程 / The Journey](#折腾历程--the-journey)
- [文件结构 / Repository Structure](#文件结构--repository-structure)
- [致谢 / Acknowledgments](#致谢--acknowledgments)
- [License](#license)
- [Contributing](#contributing)

---

## 功能 / Features

- **纯 Windows 原生** — 不需要 WSL、Linux 或 Docker，直接在 Windows 上运行
- **ROCm/HIP 原生加速** — 非间接翻译层，直接使用 AMD 原生计算接口
- **ABI 桥接** — 自研 Shim DLL 解决 ROCm 7.x 编译器与 5.7 运行时的版本断层
- **多显卡支持** — Vega 56/64、Radeon VII、Polaris、Navi 10 均可使用
- **ASR + TTS** — 语音识别和语音合成均支持 GPU 加速

---

## 测试环境 / Test Environment

| 组件 | 型号 |
|------|------|
| GPU | AMD Radeon RX Vega 56 (gfx900, 8GB HBM2) |
| CPU | AMD Ryzen Threadripper 2950X |
| OS | Windows 11 |
| 驱动 | Radeon-ID Sophronia 25.3.1 (社区驱动, PRO/Compute 组件) |
| ROCm 运行时 | ROCm 5.7.1 (HIP SDK, 从 AMD 官网下载安装) |
| 编译工具链 | TheRock ROCm SDK (LLVM 23.0, gfx900 内核) |

## 性能实测 / Performance Benchmarks

> 测试日期：2026-07-28 | CrispASR v0.8.14 | Vega 56/64 (gfx900, 8GB VRAM) | ROCm 5.7 + TheRock HIP (clang 23.0.0)

### ASR 语音识别 (GPU 加速)

| 模型 | 量化 | 大小 | 语言 | 音频时长 | 处理时间 | 实时率 | 状态 |
|------|------|------|------|---------|---------|--------|------|
| SenseVoice Small | Q4_K | 129MB | EN | 11.0s | 0.47s | **23.6x** | GPU 已验证 |
| SenseVoice Small | Q4_K | 129MB | ZH | 13.1s | 0.47s | **27.7x** | GPU 已验证 |
| Qwen3-ASR 0.6B | Q4_K | 602MB | EN | 11.0s | 2.66s | 4.1x | GPU 已验证 |
| Qwen3-ASR 0.6B | Q4_K | 602MB | ZH | 13.1s | 3.19s | 4.1x | GPU 已验证 |
| Qwen3-ASR 1.7B | Q4_K | 1422MB | EN | 11.0s | 3.62s | 3.0x | GPU 已验证 |
| Qwen3-ASR 1.7B | Q4_K | 1422MB | ZH | 13.1s | 4.28s | 3.0x | GPU 已验证 |

### TTS 语音合成

| 模型 | 量化 | 大小 | 运行模式 | 输出时长 | 总耗时 | RTF | 状态 |
|------|------|------|---------|---------|--------|-----|------|
| Kokoro 82M | Q8_0 | 135MB | CPU (Metal-hang workaround) | 3.65s | 6.3s | ~1.7x | 已验证 |
| Qwen3-TTS 0.6B | Q8_0 | 940MB | GPU+CPU 混合 | 4.32s | 13.4s | 1.45x | 已验证 |
| Chatterbox | Q8_0 | 958MB | 全 CPU (-ng) | 3.76s | 14.9s | ~0.25x | 仅 CPU 可用 |
| F5-TTS | F16 | 953MB | GPU | — | — | — | 不可用 (FlashAttention 崩溃) |
| F5-TTS | F16 | 953MB | CPU | — | >120s | — | 不可用 (CPU 推理超时) |

### Vega GPU 兼容性说明

- **ASR 全系列可用**：SenseVoice / Qwen3-ASR 0.6B / 1.7B 均在 Vega GPU 上完美运行
- **F5-TTS 不兼容**：Vega GPU 的 FlashAttention 内核崩溃 (`fattn.cu:602`)，即使 `-nfa` 也无效；CPU 推理 32 步 ODE 超过 2 分钟无输出
- **Chatterbox 仅 CPU**：GPU 模式 S3Gen UNet 崩溃 (`Module not initialized`)，S3Gen CPU 回退也失败 (buffer 断言错误)，只有全 CPU 模式 (`-ng`) 可工作
- **Qwen3-TTS 混合模式**：Talker 在 CPU 运行，Codec 在 GPU 运行，FlashAttention 不支持时自动回退到调度器路径

---

## 快速上手 / Quick Start

### 前置条件 / Prerequisites

- AMD Vega 56/64 (gfx900) 或兼容显卡
- Windows 10/11
- Visual Studio 2022 (C++ 工作负载)
- Python 3.10+ (用于安装 TheRock SDK)

### 1. 安装驱动与运行时 / Install Driver & Runtime

1. 下载 DDU (Display Driver Uninstaller)
2. 安全模式下彻底清除现有 AMD 驱动
3. 安装 **Radeon-ID Sophronia 25.3.1** 社区驱动
   - 下载地址：[SourceForge - WHQL-R-ID-Software-Hybrid-25.3.1-R2.5](https://sourceforge.net/projects/radeon-id-distribution/files/Release%20Polaris-Vega-Navi/WHQL-R-ID-Software-Hybrid-25.3.1-R2.5-Win10-Win11-PolarisVegaNavi-Sophronia.7z/download)
   - 选择 Enterprise/PRO/Compute 组件
4. 从 AMD 官网下载并安装 **HIP SDK 5.7.1**
   - 安装包文件名：`AMD-Software-PRO-Edition-23.Q4-Win10-Win11-For-HIP.exe`
   - 下载页面：https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html
   - 安装后目录为 `C:\Program Files\AMD\ROCm\5.7`（路径只含主次版本号，不显示补丁号 .1，属正常现象）
5. 替换 gfx900 专用的 rocBLAS 库
   - 下载 `rocm.gfx800-gfx900-for.hip.sdk.5.7.1-and-6.2.4.7z`
   - 来源：[advanced-lvl-up/Rx470-Vega10-Rx580-gfx803-gfx900-fix-AMD-GPU](https://github.com/advanced-lvl-up/Rx470-Vega10-Rx580-gfx803-gfx900-fix-AMD-GPU/releases/tag/v1.0.0)
   - 解压后将 `rocblas.dll` 替换到 `C:\Program Files\AMD\ROCm\5.7\bin\`
   - 将 `rocblas\library` 文件夹替换到 `C:\Program Files\AMD\ROCm\5.7\bin\rocblas\library`

### 2. 安装 TheRock ROCm SDK

```powershell
python -m venv therock\venv
therock\venv\Scripts\Activate.ps1
pip install therock-tools
therock install --device-gfx900
```

### 3. 一键编译 / One-Click Build

本仓库已包含 CrispASR 源码（`crispasr/` 目录，补丁已应用）和 ggml 源码，无需额外克隆。

```powershell
# 克隆本仓库
git clone https://github.com/A-XIANGQAQ/crispasr-vega-rocm.git
cd crispasr-vega-rocm

# 一键编译（自动镜像到无空格路径 → 编译 CrispASR → 编译 Shim DLL → 部署 DLL）
powershell -ExecutionPolicy Bypass -File scripts\build-all.ps1
```

> **注意**：`build-all.ps1` 会自动处理 hipcc 不支持空格路径的问题（镜像到 `C:\cabuild\crispasr`）、code object v4 兼容性、`-j 2` 并行度等所有已知坑点。

<details>
<summary>手动分步编译（高级） / Manual Build (Advanced)</summary>

```powershell
# 1. 镜像源码到无空格路径
robocopy crispasr C:\cabuild\crispasr /MIR /XD .git /XF *.gguf *.wav

# 2. 编译 CrispASR
cd C:\cabuild\crispasr
powershell -ExecutionPolicy Bypass -File ..\..\scripts\build-hip-therock.ps1 -SourceDir C:\cabuild\crispasr

# 3. 编译 Shim DLL（在 VS 2022 Developer Command Prompt 中）
cl /O2 /GS- /c hip-shim\hip_shim.c
link /DLL /OUT:amdhip64_7.dll hip_shim.obj /DEF:hip-shim\hip_shim.def /NODEFAULTLIB kernel32.lib
```
</details>

### 4. 运行 / Run

```batch
set HSA_OVERRIDE_GFX_VERSION=9.0.0
set HSA_ENABLE_SDMA=0
set HIP_VISIBLE_DEVICES=0

:: ASR - 自动下载模型 (-m auto)
bin-hip\crispasr.exe -m auto -f audio.wav

:: 指定后端
bin-hip\crispasr.exe --backend sensevoice -m auto -f audio.wav

:: TTS - 语音合成
bin-hip\crispasr.exe --backend kokoro -m auto --tts "Hello world" --tts-output out.wav
bin-hip\crispasr.exe --backend qwen3 -m auto --tts "你好世界" --tts-output out.wav

:: 诊断
bin-hip\crispasr.exe --diagnostics
```

> `-m auto` 会自动从 HuggingFace 下载所需模型到 `~/.cache/crispasr/`，无需手动下载。

### 环境变量说明 / Environment Variables

| 变量 | 值 | 说明 |
|------|----|------|
| `HSA_OVERRIDE_GFX_VERSION` | `9.0.0` | 架构欺骗，Vega 必须 |
| `HSA_ENABLE_SDMA` | `0` | 禁用 SDMA，防止 Vega 模型加载挂起 |
| `HIP_VISIBLE_DEVICES` | `0` | 使用第一个 GPU |

---

## 脚本说明 / Scripts

| 脚本 | 平台 | 用途 | 验证状态 |
|------|------|------|----------|
| `scripts/build-all.ps1` | Windows | **一键编译**（推荐）：镜像→编译→Shim DLL→部署 DLL | **已验证** |
| `scripts/build-hip-therock.ps1` | Windows | 仅编译 CrispASR（需手动处理镜像和 DLL） | **已验证** |
| `scripts/run_crispasr_hip.bat` | Windows | 运行 crispasr，自动设环境变量 | **已验证** |
| `scripts/build-hip.bat` | Windows | 用官方 HIP SDK 编译（备选） | 未验证 |
| `scripts/build-hip-linux.sh` | Linux/WSL2 | Linux 下编译 | 编译通过，运行未验证（Vega WSL2 无 GPU 直通） |
| `scripts/run_crispasr_hip-linux.sh` | Linux/WSL2 | Linux 下运行 | 未验证 |
| `scripts/run_crispasr_vulkan.bat` | Windows | Vulkan 后端运行（备选） | 未验证（CrispASR 官方称 Vulkan 在 AMD 上会出错） |

> **注意**：实际只需 `scripts/build-all.ps1` + `scripts/run_crispasr_hip.bat` 两个脚本即可在 Windows 上完成编译和运行。其他脚本为备选方案，供不同环境参考。

---

## 关键技术要点 / Key Technical Points

### 1. 为什么需要 Shim DLL？ / Why a Shim DLL?

TheRock 的 hipcc (ROCm 7.x ABI) 编译的二进制期望 `hipDeviceProp_t` 的 7.x 布局 (1472 字节, 含 uuid/luid/132 个字段)，但 ROCm 5.7 运行时返回的是 5.7 布局 (约 800 字节, 无 uuid/luid)。Shim DLL 在中间做结构体翻译。

### 2. 为什么需要 Code Object v4？ / Why Code Object v4?

TheRock 的 LLVM 23.0 默认生成 v5 code object，但 ROCm 5.7 的 `amd_comgr.dll` 只能解析 v4。编译时加 `-mcode-object-version=4` 即可兼容。

### 3. 为什么不能用官方驱动？ / Why Not the Official Driver?

AMD 官方 Adrenalin 驱动不暴露 ROCm/HIP 计算接口给 Vega 显卡。Sophronia 社区驱动是基于 AMD 企业驱动的修改版，启用了被官方隐藏的 Compute 组件。

### 4. 为什么 Kokoro TTS 走 CPU？ / Why Does Kokoro TTS Use CPU?

Kokoro 模型在 CrispASR 中有内置的 "Metal-hang workaround"，强制 `gen=CPU`。这不是 Vega 的问题，是所有平台的行为。Qwen3-TTS 则正常使用 GPU。

---

## 踩坑清单 / Common Pitfalls

| 坑 | 现象 | 解决方案 |
|----|------|----------|
| HIP SDK 版本显示 | 下载 5.7.1，安装后目录显示 5.7 | 正常现象，ROCm 目录名只含主次版本号 |
| rocBLAS 不支持 gfx900 | 运行时报 "invalid device function" | 用 advanced-lvl-up 项目的 gfx800-gfx900 库替换 |
| 官方驱动无 ROCm 支持 | "no ROCm-capable device is detected" | 必须用 Sophronia 社区驱动，官方 Adrenalin 不行 |
| hipcc 路径含空格崩溃 | 编译器报错或静默退出 | 将源码镜像到无空格路径再编译 |
| code object v5 不兼容 | "shared object initialization failed" | 编译加 `-mcode-object-version=4` |
| ROCm 7.x vs 5.7 ABI 不兼容 | STATUS_ENTRYPOINT_NOT_FOUND | 需要编译 Shim DLL 桥接两个版本 |
| clang 前端崩溃 | 编译中途内存不足退出 | 降到 `-j 2` 并行度 |
| Vega 模型加载挂起 | 加载模型时卡死 | 设置 `HSA_ENABLE_SDMA=0` |

---

## 适用显卡 / Supported GPUs

| 架构 | GPU | gfx ID | HSA_OVERRIDE |
|------|-----|--------|-------------|
| Vega | RX Vega 56/64 | gfx900 | 9.0.0 |
| Vega | Radeon VII | gfx906 | 9.0.6 |
| Polaris | RX 470/480/570/580 | gfx803 | 8.0.3 |
| Navi 10 | RX 5700/5700 XT | gfx1010 | 10.1.0 |

---

## 折腾历程 / The Journey

> 以下是不被官方支持的 AMD Vega 显卡上跑通 ROCm 的完整记录。
> A complete log of getting ROCm working on officially unsupported AMD Vega GPUs.

### 背景 / Background

CrispASR 是一个基于 ggml 的语音识别/合成工具。官方明确表示 Vulkan 后端在 AMD 显卡上会出错，所以唯一的选择是 HIP/ROCm。但问题在于：

- **AMD 官方 Adrenalin 驱动不支持 Vega 的 ROCm/HIP 计算接口**
- **ROCm 6.x 已移除 gfx900 (Vega) 内核支持**
- **WSL2 对 Vega 没有 GPU 直通 (librocdxg 仅支持 RDNA2+)**

这意味着常规方案全部走不通。但我手里就一张 Vega 56，我一定要用 ROCm 来搞。

### 阶段一：WSL2 尝试 (失败) / Phase 1: WSL2 Attempt (Failed)

最初我在 WSL2 Ubuntu 中安装 ROCm。`hipcc` 和 `rocblas` 都能装上，但 `/dev/dri` 目录根本不存在 — Vega 显卡在 WSL2 中没有 GPU 直通支持。`librocdxg` 库只支持 RDNA2 及以上架构，连直通的机会都没有。

**结论**：WSL2 路线对 Vega 死路一条。

### 阶段二：OpenCL 后端 (部分成功) / Phase 2: OpenCL Backend (Partial Success)

我发现 ggml 支持 OpenCL 后端，不需要 HIP SDK。成功编译了 OpenCL 版本，但发现 ggml-opencl 的 GPU 家族检测代码直接排除了 AMD 桌面显卡。我修改了 `ggml-opencl.cpp`，添加了 AMD Vega/GCN 支持（wave size = 64），编译成功。

但 OpenCL 性能不理想，而且我一定要用 ROCm 来搞。这不是能不能跑的问题，是我就要证明 Vega 也能用 ROCm。

### 阶段三：GHOST + ZLUDA (间接方案) / Phase 3: GHOST + ZLUDA (Indirect)

我研究了 GHOST (AMD-Ghost-Environment) 工具，它是一个 Windows 原生的 ROCm/ZLUDA 注入器，明确支持 Vega 56/64。同时下载了 ZLUDA (CUDA-to-ROCm 翻译层)。

但这些是 CUDA 兼容层，不是原生 HIP，无法用于 CrispASR 的 ggml HIP 后端。方向不对。

### 阶段四：TheRock ROCm SDK (突破口) / Phase 4: TheRock ROCm SDK (Breakthrough)

我发现了 AMD 的 TheRock 项目 — ROCm 的 Windows 原生计划。通过 pip 安装了 TheRock ROCm SDK，包含：

- `hipcc.exe` 编译器 (LLVM 23.0)
- `rocblas.dll` + gfx900 专用内核
- `hipblas.dll`
- 完整的 ROCm 开发工具链

这是第一个真正的突破：**终于有了能编译 gfx900 代码的 hipcc**。

### 阶段五：编译地狱 / Phase 5: Compilation Hell

用 TheRock 的 hipcc 编译 CrispASR，我遇到了一连串问题，一个接一个地踩：

1. **路径含空格** — 源码目录路径中的空格导致 hipcc 崩溃。用 robocopy 镜像到一个无空格的路径解决
2. **ROCm 设备库缺失** — 修改 `hipcc.bat` 添加 `--rocm-path` 和 `--rocm-device-lib-path`
3. **cmath 头冲突** — MSVC 和 ROCm clang 的 cmath 头文件冲突，添加前向声明解决
4. **版本宏引号问题** — `GGML_VERSION` 和 `GGML_COMMIT` 宏的字符串化问题，在多个文件中添加 stringification 宏
5. **CMAKE_AR 缺失** — 显式设置 `CMAKE_AR` 和 `CMAKE_RANLIB` 指向 llvm-ar.exe
6. **unistd.h 缺失** — Windows 不兼容的测试代码，禁用测试 (`-DCRISPASR_BUILD_TESTS=OFF`)
7. **setenv/unsetenv** — POSIX 函数在 Windows 不存在，用 `_putenv_s` 实现
8. **__cpu_model 链接错误** — 缺少 clang builtins 库，添加 `clang_rt.builtins-x86_64.lib`
9. **Ninja 路径无效** — WinGet 的 ninja 链接失效，手动指定正确路径

最终编译成功，生成了 `crispasr.exe` 和 `ggml-hip.dll`。

### 阶段六：驱动与 GPU 检测 / Phase 6: Driver & GPU Detection

编译成功后一运行，报 "no ROCm-capable device is detected"。

**根因**：AMD 官方 Adrenalin 26.5.2 驱动不支持 Vega 的 ROCm 计算接口。

**解决方案**：
1. 用 DDU (Display Driver Uninstaller) 在安全模式下彻底清除官方驱动
2. 安装 **Radeon-ID Sophronia 25.3.1** 社区驱动，选择 Enterprise/PRO/Compute 组件
3. 安装后 GPU 被识别为 "Radeon Instinct MI25" (Vega 56 的计算变体)
4. 从 AMD 官网单独下载并安装 ROCm 5.7.1 运行时

GPU 成功检测：`Radeon RX Vega, gfx900:xnack-, VRAM: 8176 MiB`

### 阶段七：DLL 依赖地狱 / Phase 7: DLL Dependency Hell

运行 crispasr.exe 报退出码 -1073741515 (DLL not found)。我系统性排查发现缺失大量 ROCm DLL，写了递归依赖解析器，自动从 ROCm 5.7 和 TheRock SDK 中查找并复制所有依赖 DLL。

关键缺失：`origami.dll`, `rocm_kpack.dll`, `libomp140.x86_64.dll` 等。

### 阶段八：ROCm 7.x vs 5.7 ABI 不兼容 (最难的坑) / Phase 8: ABI Incompatibility (Hardest Bug)

DLL 齐全后，报 `STATUS_ENTRYPOINT_NOT_FOUND (0xC0000139)`。

**根因**：CrispASR 用 TheRock 的 ROCm 7.x hipcc 编译，但运行时用的是 ROCm 5.7 的 DLL。7.x 的 `hipDeviceProp_t` 结构体布局与 5.7 完全不同，且 7.x 新增了 `hipGetDevicePropertiesR0600` 符号在 5.7 中不存在。

**解决方案**：我编写了 **ABI 桥接 Shim DLL** (`amdhip64_7.dll`)：

- 将 60+ 个 HIP 函数直接转发到 ROCm 5.7 的 `amdhip64.dll`
- 手动实现 `hipGetDevicePropertiesR0600`：调用 5.7 的 `hipGetDeviceProperties`，然后将 5.7 的结构体逐字段翻译到 7.x 的布局
- 实现 `hipDrvLaunchKernelEx` 桩函数 (返回 hipErrorNotSupported)
- 无 CRT 依赖，手工 kernel32 导入，避免任何运行时冲突

Shim DLL 编译也有坑：link.exe 的 forwarder 语法、import library 生成、security cookie 错误 (`/GS-` 禁用)。

### 阶段九：Code Object 版本不匹配 / Phase 9: Code Object Version Mismatch

ABI 桥接成功后，GPU 检测正常，但 TTS 运行报 "shared object initialization failed"。

**根因**：TheRock 的 LLVM 23.0 默认生成 code object v5，但 ROCm 5.7 的 `amd_comgr.dll` 只能解析 v4 及以下。

**尝试过程**：
1. 先试 `-mcode-object-version=3` — TheRock clang 报错 "invalid integral value '3'"，v3 已在新版 LLVM 中移除
2. 改用 `-mcode-object-version=4` — 编译成功
3. 但第一次链接失败：找不到 `amdhip64.lib` — 将 TheRock 的 lib 路径加入 `LIB` 环境变量
4. 编译到 38/91 时 clang 前端崩溃 (内存不足) — 降到 `-j 2` 并行度
5. 最终 54 个编译步骤全部成功，`ggml-hip.dll` 重新生成

同时恢复了 ROCm 5.7 版本的 `amd_comgr.dll` (100.5MB)，替换 TheRock 的新版本 (121MB)。

### 最终结果 / Final Result

```
ggml_cuda_init: found 1 ROCm devices (Total VRAM: 8176 MiB):
  Device 0: Radeon RX Vega, gfx900:xnack- (0x900), VMM: no, Wave Size: 64, VRAM: 8176 MiB

ASR: SenseVoice Small  23.6-27.7x realtime (GPU)
ASR: Qwen3-ASR 0.6B    4.1x realtime (GPU)
ASR: Qwen3-ASR 1.7B    3.0x realtime (GPU)
TTS: Kokoro 82M        ~1.7x RTF (CPU)
TTS: Qwen3-TTS 0.6B    1.45x RTF (GPU+CPU)
```

---

## 文件结构 / Repository Structure

```
crispasr-vega-rocm/
├── README.md                  # 本文档 / This document
├── LICENSE                    # MIT 许可证 (Shim DLL 代码) / MIT License
├── .gitignore
├── hip-shim/                  # ABI 桥接 Shim DLL 源码 / ABI bridge source
│   ├── hip_shim.c             # ROCm 7.x → 5.7 结构体翻译 / Struct translation
│   └── hip_shim.def           # 60+ 符号转发定义 / 60+ symbol forwards
├── scripts/                   # 构建和运行脚本 / Build and run scripts
│   ├── build-all.ps1          # 一键编译 (已验证) / One-click build (verified)
│   ├── build-hip-therock.ps1  # 仅编译 CrispASR (已验证) / Build only (verified)
│   ├── run_crispasr_hip.bat   # Windows 运行脚本 (已验证) / Windows run (verified)
│   ├── build-hip.bat          # 通用 HIP 编译 (未验证) / Generic HIP build (unverified)
│   ├── build-hip-linux.sh     # Linux/WSL2 编译 (未验证) / Linux build (unverified)
│   ├── run_crispasr_hip-linux.sh # Linux 运行 (未验证) / Linux run (unverified)
│   └── run_crispasr_vulkan.bat   # Vulkan 后端 (未验证) / Vulkan backend (unverified)
├── crispasr/                  # CrispASR 源码 (补丁已应用) / Source (pre-patched)
│   ├── CMakeLists.txt         # 根 CMake (含 Windows 兼容性修复)
│   ├── src/                   # 核心源码 (43 ASR + 48 TTS 后端)
│   ├── ggml/                  # ggml 源码 (含 HIP 后端, code object v4)
│   ├── examples/              # CLI 源码
│   ├── include/               # 头文件
│   ├── cmake/                 # CMake 模块
│   ├── crisp_audio/           # 音频处理
│   ├── crisp_lid/             # 语言识别
│   ├── crisp_punc/            # 标点恢复
│   ├── crisp_truecase/        # 大小写归一化
│   ├── third_party/           # OpenCL 头文件 + c2pa-audio
│   ├── models/                # 模型配置 (模型文件运行时自动下载)
│   ├── samples/               # 测试音频
│   ├── tools/                 # 工具
│   └── VERSION
├── patches/                   # 源码补丁 (已应用, 供参考) / Patches (applied, for reference)
│   ├── 01-cmake-fixes.patch
│   ├── 02-crispasr-windows-fixes.patch
│   ├── 03-diagnostics-windows-fixes.patch
│   ├── 04-diff-main-windows-fixes.patch
│   └── 05-cli-cmake-fixes.patch
└── bin-hip/                   # 编译输出 (gitignore, 需自行编译) / Build output
    ├── crispasr.exe           # 主程序
    ├── ggml-hip.dll           # HIP 后端 (code object v4)
    ├── amdhip64_7.dll         # ABI Shim (7.x → 5.7)
    └── ...                    # ROCm 运行时 DLL
```

---

## 致谢 / Acknowledgments

- [TheRock](https://github.com/ROCm/TheRock) — AMD 的 ROCm Windows 原生计划 / AMD's native Windows ROCm initiative
- [Radeon-ID Sophronia](https://www.guru3d.com/download/radeon-id-sophronia-driver/) — 社区修改驱动，启用 Vega Compute 组件 / Community driver enabling Vega Compute
- [advanced-lvl-up/Rx470-Vega10-Rx580-gfx803-gfx900-fix-AMD-GPU](https://github.com/advanced-lvl-up/Rx470-Vega10-Rx580-gfx803-gfx900-fix-AMD-GPU) — gfx800/gfx900 专用 rocBLAS 库 / Prebuilt rocBLAS for gfx800/gfx900
- [AMD HIP SDK 5.7.1](https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html) — Windows ROCm 运行时 / Windows ROCm runtime
- [CrispASR](https://github.com/crisp-asr/crispasr) — ggml 语音工具 / ggml-based speech toolkit
- [GHOST](https://github.com/likelovewant/GHOST) — AMD GPU 环境管理工具 (参考) / AMD GPU environment manager (reference)
- [likelovewant/ROCmLibs-for-gfx1103-AMD780M-APU](https://github.com/likelovewant/ROCmLibs-for-gfx1103-AMD780M-APU) — ROCm 社区库构建参考 / Community ROCm library build reference

---

## License

Shim DLL 代码（`hip-shim/`）和构建脚本（`scripts/`）采用 MIT 许可证，可自由使用。
源码补丁（`patches/`）基于 CrispASR 原始代码生成，遵循 CrispASR 的原始许可证。

Shim DLL code (`hip-shim/`) and build scripts (`scripts/`) are released under the MIT License and are free to use.
Source patches (`patches/`) are derived from CrispASR source code and follow CrispASR's original license.

---

## Contributing

欢迎提交 Issue 和 PR！

- 如果你在其他 AMD 显卡（Polaris、Navi 10 等）上测试成功，请开 Issue 告知
- 如果发现新的踩坑点，欢迎补充到踩坑清单
- Shim DLL 如需支持更多 ROCm 版本组合，欢迎提交 PR

Issues and PRs are welcome!

- If you successfully test on other AMD GPUs (Polaris, Navi 10, etc.), please open an Issue
- If you find new pitfalls, feel free to add them to the Common Pitfalls table
- If the Shim DLL needs to support more ROCm version combinations, PRs are welcome
