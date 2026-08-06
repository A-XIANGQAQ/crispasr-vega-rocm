/*
 * amdhip64_7.dll shim: translates ROCm 7.x ABI (TheRock) to ROCm 5.7 runtime.
 *
 * - 60+ symbols are forwarded directly to amdhip64.dll (ROCm 5.7) via
 *   #pragma comment(linker, "/export:xxx=amdhip64.xxx") forwarders below.
 *   (Do NOT use a .def file — MSVC 14.51 link.exe silently ignores .def
 *   forwarders, leaving entry points unresolved at load time.)
 * - hipGetDeviceProperties / hipGetDevicePropertiesR0600 are implemented locally:
 *   they call ROCm 5.7's hipGetDeviceProperties and translate the 5.7
 *   hipDeviceProp_t layout into the 7.x layout that TheRock-built binaries
 *   (e.g. ggml-hip.dll) expect.  Forwarding these would return misaligned fields
 *   (garbage cc/warpSize/VRAM) because of the 5.7→7.x layout difference.
 *
 * No CRT dependency: manual kernel32 imports + tiny mem helpers.
 */

typedef unsigned int uint;
typedef unsigned long long size64;
typedef __int64 ssize64;

#ifndef SIZE_T_DEFINED
#define SIZE_T_DEFINED
typedef unsigned __int64 size_t_shim;
#endif

/* ---- kernel32 imports (avoid windows.h) ---- */
__declspec(dllimport) void* __stdcall LoadLibraryA(const char* lpLibFileName);
__declspec(dllimport) void* __stdcall GetProcAddress(void* hModule, const char* lpProcName);
__declspec(dllimport) void* __stdcall GetModuleHandleA(const char* lpModuleName);
__declspec(dllimport) void* __stdcall CreateFileA(const char* fn, unsigned long acc, unsigned long share, void* sa, unsigned long disp, unsigned long flags, void* tmpl);
__declspec(dllimport) int __stdcall WriteFile(void* h, const void* buf, unsigned long len, unsigned long* written, void* ov);
__declspec(dllimport) int __stdcall CloseHandle(void* h);

/* ---- debug dump helper (CRT-free) ---- */
static void shim_debug_dump(const char* fn, const void* data, unsigned long len) {
    void* h = CreateFileA(fn, 0x40000000, 0, 0, 2, 0x80, 0); /* GENERIC_WRITE, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL */
    if (h == (void*)-1) return;
    WriteFile(h, data, len, &len, 0);
    CloseHandle(h);
}

/* ======================================================================
 * DLL forwarders: export symbols from this DLL but forward them directly
 * to amdhip64.dll (ROCm 5.7 runtime).  The "othermodule.function" syntax
 * with a dot tells link.exe to create a forwarder export, not an alias.
 * This replaces the .def-based forwarding that MSVC 14.51 link.exe was
 * silently ignoring (treating entries as unresolved externals).
 * ==================================================================== */
#pragma comment(linker, "/export:__hipPopCallConfiguration=amdhip64.__hipPopCallConfiguration")
#pragma comment(linker, "/export:__hipPushCallConfiguration=amdhip64.__hipPushCallConfiguration")
#pragma comment(linker, "/export:__hipRegisterFatBinary=amdhip64.__hipRegisterFatBinary")
#pragma comment(linker, "/export:__hipRegisterFunction=amdhip64.__hipRegisterFunction")
#pragma comment(linker, "/export:__hipUnregisterFatBinary=amdhip64.__hipUnregisterFatBinary")
#pragma comment(linker, "/export:hipDeviceCanAccessPeer=amdhip64.hipDeviceCanAccessPeer")
#pragma comment(linker, "/export:hipDeviceEnablePeerAccess=amdhip64.hipDeviceEnablePeerAccess")
#pragma comment(linker, "/export:hipDeviceGetAttribute=amdhip64.hipDeviceGetAttribute")
#pragma comment(linker, "/export:hipDeviceGetDefaultMemPool=amdhip64.hipDeviceGetDefaultMemPool")
#pragma comment(linker, "/export:hipDeviceSynchronize=amdhip64.hipDeviceSynchronize")
#pragma comment(linker, "/export:hipEventCreate=amdhip64.hipEventCreate")
#pragma comment(linker, "/export:hipEventCreateWithFlags=amdhip64.hipEventCreateWithFlags")
#pragma comment(linker, "/export:hipEventDestroy=amdhip64.hipEventDestroy")
#pragma comment(linker, "/export:hipFuncSetAttribute=amdhip64.hipFuncSetAttribute")
#pragma comment(linker, "/export:hipEventElapsedTime=amdhip64.hipEventElapsedTime")
#pragma comment(linker, "/export:hipEventRecord=amdhip64.hipEventRecord")
#pragma comment(linker, "/export:hipEventSynchronize=amdhip64.hipEventSynchronize")
#pragma comment(linker, "/export:hipExtGetLastError=amdhip64.hipGetLastError")
#pragma comment(linker, "/export:hipExtModuleLaunchKernel=amdhip64.hipExtModuleLaunchKernel")
#pragma comment(linker, "/export:hipFree=amdhip64.hipFree")
#pragma comment(linker, "/export:hipFreeAsync=amdhip64.hipFreeAsync")
#pragma comment(linker, "/export:hipGetDevice=amdhip64.hipGetDevice")
#pragma comment(linker, "/export:hipGetDeviceCount=amdhip64.hipGetDeviceCount")
#pragma comment(linker, "/export:hipGetErrorName=amdhip64.hipGetErrorName")
#pragma comment(linker, "/export:hipGetErrorString=amdhip64.hipGetErrorString")
#pragma comment(linker, "/export:hipGetLastError=amdhip64.hipGetLastError")
#pragma comment(linker, "/export:hipGetStreamDeviceId=amdhip64.hipGetStreamDeviceId")
#pragma comment(linker, "/export:hipHostFree=amdhip64.hipHostFree")
#pragma comment(linker, "/export:hipHostGetDevicePointer=amdhip64.hipHostGetDevicePointer")
#pragma comment(linker, "/export:hipHostMalloc=amdhip64.hipHostMalloc")
#pragma comment(linker, "/export:hipHostRegister=amdhip64.hipHostRegister")
#pragma comment(linker, "/export:hipHostUnregister=amdhip64.hipHostUnregister")
#pragma comment(linker, "/export:hipLaunchCooperativeKernel=amdhip64.hipLaunchCooperativeKernel")
#pragma comment(linker, "/export:hipLaunchKernel=amdhip64.hipLaunchKernel")
#pragma comment(linker, "/export:hipMalloc=amdhip64.hipMalloc")
#pragma comment(linker, "/export:hipMallocAsync=amdhip64.hipMallocAsync")
#pragma comment(linker, "/export:hipMallocManaged=amdhip64.hipMallocManaged")
#pragma comment(linker, "/export:hipMemAdvise=amdhip64.hipMemAdvise")
#pragma comment(linker, "/export:hipMemcpy=amdhip64.hipMemcpy")
#pragma comment(linker, "/export:hipMemcpy2D=amdhip64.hipMemcpy2D")
#pragma comment(linker, "/export:hipMemcpy2DAsync=amdhip64.hipMemcpy2DAsync")
#pragma comment(linker, "/export:hipMemcpyAsync=amdhip64.hipMemcpyAsync")
#pragma comment(linker, "/export:hipMemcpyPeerAsync=amdhip64.hipMemcpyPeerAsync")
/* hipMemGetInfo: local implementation with fallback (see below) */
#pragma comment(linker, "/export:hipMemPoolTrimTo=amdhip64.hipMemPoolTrimTo")
#pragma comment(linker, "/export:hipMemset=amdhip64.hipMemset")
#pragma comment(linker, "/export:hipMemsetAsync=amdhip64.hipMemsetAsync")
#pragma comment(linker, "/export:hipModuleGetFunction=amdhip64.hipModuleGetFunction")
#pragma comment(linker, "/export:hipModuleLoad=amdhip64.hipModuleLoad")
#pragma comment(linker, "/export:hipModuleLoadData=amdhip64.hipModuleLoadData")
#pragma comment(linker, "/export:hipModuleOccupancyMaxActiveBlocksPerMultiprocessor=amdhip64.hipModuleOccupancyMaxActiveBlocksPerMultiprocessor")
#pragma comment(linker, "/export:hipModuleUnload=amdhip64.hipModuleUnload")
#pragma comment(linker, "/export:hipOccupancyMaxActiveBlocksPerMultiprocessor=amdhip64.hipOccupancyMaxActiveBlocksPerMultiprocessor")
#pragma comment(linker, "/export:hipPointerGetAttributes=amdhip64.hipPointerGetAttributes")
#pragma comment(linker, "/export:hipRuntimeGetVersion=amdhip64.hipRuntimeGetVersion")
#pragma comment(linker, "/export:hipSetDevice=amdhip64.hipSetDevice")
#pragma comment(linker, "/export:hipStreamCreateWithFlags=amdhip64.hipStreamCreateWithFlags")
#pragma comment(linker, "/export:hipStreamDestroy=amdhip64.hipStreamDestroy")
#pragma comment(linker, "/export:hipStreamIsCapturing=amdhip64.hipStreamIsCapturing")
#pragma comment(linker, "/export:hipStreamQuery=amdhip64.hipStreamQuery")
#pragma comment(linker, "/export:hipStreamSynchronize=amdhip64.hipStreamSynchronize")
#pragma comment(linker, "/export:hipStreamWaitEvent=amdhip64.hipStreamWaitEvent")

/* hipGetDeviceProperties / hipGetDevicePropertiesR0600 are implemented locally
 * (structure translation from ROCm 5.7 layout to 7.x layout).  ggml-hip.dll is
 * compiled against TheRock 7.x headers: it calls hipGetDevicePropertiesR0600 and
 * reads the returned struct using the 7.x layout (1472 bytes).  Forwarding straight
 * to amdhip64.dll would hand back the 5.7 layout (~800 bytes) → field misalignment
 * → garbage cc/warpSize/VRAM.  So we MUST export the translating implementation.
 * The function hipGetDevicePropertiesR0600 is defined below with __declspec(dllexport);
 * hipGetDeviceProperties is aliased to it. */
#pragma comment(linker, "/export:hipGetDeviceProperties=hipGetDevicePropertiesR0600")

/* ---- tiny CRT-free helpers ---- */
static void shim_zero(void* p, size_t_shim n) {
    unsigned char* b = (unsigned char*)p;
    while (n--) *b++ = 0;
}
static void shim_copy(void* d, const void* s, size_t_shim n) {
    unsigned char* dd = (unsigned char*)d;
    const unsigned char* ss = (const unsigned char*)s;
    while (n--) *dd++ = *ss++;
}

/* ======================================================================
 * Shared arch bitfield struct (identical in ROCm 5.7 and 7.x headers)
 * ==================================================================== */
typedef struct {
    unsigned hasGlobalInt32Atomics : 1;
    unsigned hasGlobalFloatAtomicExch : 1;
    unsigned hasSharedInt32Atomics : 1;
    unsigned hasSharedFloatAtomicExch : 1;
    unsigned hasFloatAtomicAdd : 1;
    unsigned hasGlobalInt64Atomics : 1;
    unsigned hasSharedInt64Atomics : 1;
    unsigned hasDoubles : 1;
    unsigned hasWarpVote : 1;
    unsigned hasWarpBallot : 1;
    unsigned hasWarpShuffle : 1;
    unsigned hasFunnelShift : 1;
    unsigned hasThreadFenceSystem : 1;
    unsigned hasSyncThreadsExt : 1;
    unsigned hasSurfaceFuncs : 1;
    unsigned has3dGrid : 1;
    unsigned hasDynamicParallelism : 1;
} hipDeviceArch_t;

/* ======================================================================
 * ROCm 5.7 hipDeviceProp_t (verbatim field order from 5.7 header)
 * ==================================================================== */
typedef struct hipDeviceProp57 {
    char name[256];
    size_t_shim totalGlobalMem;
    size_t_shim sharedMemPerBlock;
    int regsPerBlock;
    int warpSize;
    int maxThreadsPerBlock;
    int maxThreadsDim[3];
    int maxGridSize[3];
    int clockRate;
    int memoryClockRate;
    int memoryBusWidth;
    size_t_shim totalConstMem;
    int major;
    int minor;
    int multiProcessorCount;
    int l2CacheSize;
    int maxThreadsPerMultiProcessor;
    int computeMode;
    int clockInstructionRate;
    hipDeviceArch_t arch;
    int concurrentKernels;
    int pciDomainID;
    int pciBusID;
    int pciDeviceID;
    size_t_shim maxSharedMemoryPerMultiProcessor;
    int isMultiGpuBoard;
    int canMapHostMemory;
    int gcnArch;
    char gcnArchName[256];
    int integrated;
    int cooperativeLaunch;
    int cooperativeMultiDeviceLaunch;
    int maxTexture1DLinear;
    int maxTexture1D;
    int maxTexture2D[2];
    int maxTexture3D[3];
    unsigned int* hdpMemFlushCntl;
    unsigned int* hdpRegFlushCntl;
    size_t_shim memPitch;
    size_t_shim textureAlignment;
    size_t_shim texturePitchAlignment;
    int kernelExecTimeoutEnabled;
    int ECCEnabled;
    int tccDriver;
    int cooperativeMultiDeviceUnmatchedFunc;
    int cooperativeMultiDeviceUnmatchedGridDim;
    int cooperativeMultiDeviceUnmatchedBlockDim;
    int cooperativeMultiDeviceUnmatchedSharedMem;
    int isLargeBar;
    int asicRevision;
    int managedMemory;
    int directManagedMemAccessFromHost;
    int concurrentManagedAccess;
    int pageableMemoryAccess;
    int pageableMemoryAccessUsesHostPageTables;
} hipDeviceProp57;

/* ======================================================================
 * ROCm 7.x hipDeviceProp_t (verbatim field order from TheRock header)
 * ==================================================================== */
typedef struct { char bytes[16]; } hipUUID_shim;

typedef struct hipDevicePropR0600 {
    char name[256];
    hipUUID_shim uuid;
    char luid[8];
    unsigned int luidDeviceNodeMask;
    size_t_shim totalGlobalMem;
    size_t_shim sharedMemPerBlock;
    int regsPerBlock;
    int warpSize;
    size_t_shim memPitch;
    int maxThreadsPerBlock;
    int maxThreadsDim[3];
    int maxGridSize[3];
    int clockRate;
    size_t_shim totalConstMem;
    int major;
    int minor;
    size_t_shim textureAlignment;
    size_t_shim texturePitchAlignment;
    int deviceOverlap;
    int multiProcessorCount;
    int kernelExecTimeoutEnabled;
    int integrated;
    int canMapHostMemory;
    int computeMode;
    int maxTexture1D;
    int maxTexture1DMipmap;
    int maxTexture1DLinear;
    int maxTexture2D[2];
    int maxTexture2DMipmap[2];
    int maxTexture2DLinear[3];
    int maxTexture2DGather[2];
    int maxTexture3D[3];
    int maxTexture3DAlt[3];
    int maxTextureCubemap;
    int maxTexture1DLayered[2];
    int maxTexture2DLayered[3];
    int maxTextureCubemapLayered[2];
    int maxSurface1D;
    int maxSurface2D[2];
    int maxSurface3D[3];
    int maxSurface1DLayered[2];
    int maxSurface2DLayered[3];
    int maxSurfaceCubemap;
    int maxSurfaceCubemapLayered[2];
    size_t_shim surfaceAlignment;
    int concurrentKernels;
    int ECCEnabled;
    int pciBusID;
    int pciDeviceID;
    int pciDomainID;
    int tccDriver;
    int asyncEngineCount;
    int unifiedAddressing;
    int memoryClockRate;
    int memoryBusWidth;
    int l2CacheSize;
    int persistingL2CacheMaxSize;
    int maxThreadsPerMultiProcessor;
    int streamPrioritiesSupported;
    int globalL1CacheSupported;
    int localL1CacheSupported;
    size_t_shim sharedMemPerMultiprocessor;
    int regsPerMultiprocessor;
    int managedMemory;
    int isMultiGpuBoard;
    int multiGpuBoardGroupID;
    int hostNativeAtomicSupported;
    int singleToDoublePrecisionPerfRatio;
    int pageableMemoryAccess;
    int concurrentManagedAccess;
    int computePreemptionSupported;
    int canUseHostPointerForRegisteredMem;
    int cooperativeLaunch;
    int cooperativeMultiDeviceLaunch;
    size_t_shim sharedMemPerBlockOptin;
    int pageableMemoryAccessUsesHostPageTables;
    int directManagedMemAccessFromHost;
    int maxBlocksPerMultiProcessor;
    int accessPolicyMaxWindowSize;
    size_t_shim reservedSharedMemPerBlock;
    int hostRegisterSupported;
    int sparseHipArraySupported;
    int hostRegisterReadOnlySupported;
    int timelineSemaphoreInteropSupported;
    int memoryPoolsSupported;
    int gpuDirectRDMASupported;
    unsigned int gpuDirectRDMAFlushWritesOptions;
    int gpuDirectRDMAWritesOrdering;
    unsigned int memoryPoolSupportedHandleTypes;
    int deferredMappingHipArraySupported;
    int ipcEventSupported;
    int clusterLaunch;
    int unifiedFunctionPointers;
    int reserved[63];
    int hipReserved[32];
    char gcnArchName[256];
    size_t_shim maxSharedMemoryPerMultiProcessor;
    int clockInstructionRate;
    hipDeviceArch_t arch;
    unsigned int* hdpMemFlushCntl;
    unsigned int* hdpRegFlushCntl;
    int cooperativeMultiDeviceUnmatchedFunc;
    int cooperativeMultiDeviceUnmatchedGridDim;
    int cooperativeMultiDeviceUnmatchedBlockDim;
    int cooperativeMultiDeviceUnmatchedSharedMem;
    int isLargeBar;
    int asicRevision;
} hipDevicePropR0600;

/* ---- layout sanity checks (hand-computed offsets from headers) ---- */
#define SHIM_OFFSETOF(type, field) ((size_t_shim)&(((type*)0)->field))
#define SHIM_STATIC_ASSERT(cond, msg) typedef char shim_assert_##msg[(cond) ? 1 : -1]

/* 7.x key offsets */
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDevicePropR0600, totalGlobalMem) == 288, off7_totalGlobalMem);
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDevicePropR0600, sharedMemPerBlock) == 296, off7_smpb);
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDevicePropR0600, warpSize) == 308, off7_warp);
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDevicePropR0600, major) == 360, off7_major);
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDevicePropR0600, multiProcessorCount) == 388, off7_nsm);
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDevicePropR0600, integrated) == 396, off7_integrated);
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDevicePropR0600, concurrentKernels) == 576, off7_conc);
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDevicePropR0600, pciBusID) == 584, off7_pcibus);
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDevicePropR0600, pciDomainID) == 592, off7_pcidom);
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDevicePropR0600, gcnArchName) == 1160, off7_gcn);
SHIM_STATIC_ASSERT(sizeof(hipDevicePropR0600) == 1472, size7);

/* 5.7 key offsets */
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDeviceProp57, totalGlobalMem) == 256, off57_totalGlobalMem);
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDeviceProp57, major) == 328, off57_major);
SHIM_STATIC_ASSERT(SHIM_OFFSETOF(hipDeviceProp57, gcnArchName) == 396, off57_gcn);

/* ======================================================================
 * hipGetDevicePropertiesR0600 implementation
 * ==================================================================== */
typedef int (*GetProps57Fn)(hipDeviceProp57* prop, int deviceId);
static GetProps57Fn g_pGetProps57 = 0;
static int g_resolveTried = 0;

/* Resolve ROCm 5.7's hipGetDeviceProperties from amdhip64.dll (already loaded) */
static int shim_resolve57(void) {
    void* h;
    if (g_resolveTried) return g_pGetProps57 != 0;
    g_resolveTried = 1;
    h = GetModuleHandleA("amdhip64.dll");
    if (!h) h = LoadLibraryA("amdhip64.dll");
    if (!h) return 0;
    g_pGetProps57 = (GetProps57Fn)GetProcAddress(h, "hipGetDeviceProperties");
    return g_pGetProps57 != 0;
}

__declspec(dllexport) int hipGetDevicePropertiesR0600(hipDevicePropR0600* dst, int deviceId) {
    hipDeviceProp57 src;
    int err;
    if (!dst) return 1; /* hipErrorInvalidValue */
    if (!shim_resolve57()) return 1;
    shim_zero(&src, sizeof(src));
    err = g_pGetProps57(&src, deviceId);
    if (err != 0) return err;

    shim_zero(dst, sizeof(*dst));
    /* name */
    shim_copy(dst->name, src.name, sizeof(dst->name));
    /* uuid/luid: not available in 5.7, leave zeroed */
    dst->totalGlobalMem = src.totalGlobalMem;
    dst->sharedMemPerBlock = src.sharedMemPerBlock;
    dst->regsPerBlock = src.regsPerBlock;
    dst->warpSize = src.warpSize;
    dst->memPitch = src.memPitch;
    dst->maxThreadsPerBlock = src.maxThreadsPerBlock;
    dst->maxThreadsDim[0] = src.maxThreadsDim[0];
    dst->maxThreadsDim[1] = src.maxThreadsDim[1];
    dst->maxThreadsDim[2] = src.maxThreadsDim[2];
    dst->maxGridSize[0] = src.maxGridSize[0];
    dst->maxGridSize[1] = src.maxGridSize[1];
    dst->maxGridSize[2] = src.maxGridSize[2];
    dst->clockRate = src.clockRate;
    dst->totalConstMem = src.totalConstMem;
    dst->major = src.major;
    dst->minor = src.minor;
    dst->textureAlignment = src.textureAlignment;
    dst->texturePitchAlignment = src.texturePitchAlignment;
    dst->deviceOverlap = 0;
    dst->multiProcessorCount = src.multiProcessorCount;
    dst->kernelExecTimeoutEnabled = src.kernelExecTimeoutEnabled;
    dst->integrated = src.integrated;
    dst->canMapHostMemory = src.canMapHostMemory;
    dst->computeMode = src.computeMode;
    dst->maxTexture1D = src.maxTexture1D;
    dst->maxTexture1DLinear = src.maxTexture1DLinear;
    dst->maxTexture2D[0] = src.maxTexture2D[0];
    dst->maxTexture2D[1] = src.maxTexture2D[1];
    dst->maxTexture3D[0] = src.maxTexture3D[0];
    dst->maxTexture3D[1] = src.maxTexture3D[1];
    dst->maxTexture3D[2] = src.maxTexture3D[2];
    dst->concurrentKernels = src.concurrentKernels;
    dst->ECCEnabled = src.ECCEnabled;
    dst->pciBusID = src.pciBusID;
    dst->pciDeviceID = src.pciDeviceID;
    dst->pciDomainID = src.pciDomainID;
    dst->tccDriver = src.tccDriver;
    dst->memoryClockRate = src.memoryClockRate;
    dst->memoryBusWidth = src.memoryBusWidth;
    dst->l2CacheSize = src.l2CacheSize;
    dst->maxThreadsPerMultiProcessor = src.maxThreadsPerMultiProcessor;
    dst->managedMemory = src.managedMemory;
    dst->isMultiGpuBoard = src.isMultiGpuBoard;
    dst->pageableMemoryAccess = src.pageableMemoryAccess;
    dst->concurrentManagedAccess = src.concurrentManagedAccess;
    dst->cooperativeLaunch = src.cooperativeLaunch;
    dst->cooperativeMultiDeviceLaunch = src.cooperativeMultiDeviceLaunch;
    dst->sharedMemPerBlockOptin = 0; /* not in 5.7 */
    dst->pageableMemoryAccessUsesHostPageTables = src.pageableMemoryAccessUsesHostPageTables;
    dst->directManagedMemAccessFromHost = src.directManagedMemAccessFromHost;
    shim_copy(dst->gcnArchName, src.gcnArchName, sizeof(dst->gcnArchName));
    dst->maxSharedMemoryPerMultiProcessor = src.maxSharedMemoryPerMultiProcessor;
    dst->clockInstructionRate = src.clockInstructionRate;
    dst->arch = src.arch;
    dst->hdpMemFlushCntl = src.hdpMemFlushCntl;
    dst->hdpRegFlushCntl = src.hdpRegFlushCntl;
    dst->cooperativeMultiDeviceUnmatchedFunc = src.cooperativeMultiDeviceUnmatchedFunc;
    dst->cooperativeMultiDeviceUnmatchedGridDim = src.cooperativeMultiDeviceUnmatchedGridDim;
    dst->cooperativeMultiDeviceUnmatchedBlockDim = src.cooperativeMultiDeviceUnmatchedBlockDim;
    dst->cooperativeMultiDeviceUnmatchedSharedMem = src.cooperativeMultiDeviceUnmatchedSharedMem;
    dst->isLargeBar = src.isLargeBar;
    dst->asicRevision = src.asicRevision;
    return 0; /* hipSuccess */
}

/* ======================================================================
 * hipDrvLaunchKernelEx stub
 * Not available in ROCm 5.7. Returns hipErrorNotSupported (1).
 * Only imported by libhipblaslt.dll; should not be called during
 * normal CrispASR inference workloads.
 * ==================================================================== */
__declspec(dllexport) int hipDrvLaunchKernelEx(void* a, void* b, void* c, void* d, void* e, void* f, void* g) {
    (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g;
    return 1; /* hipErrorNotSupported */
}

/* ======================================================================
 * hipMemGetInfo workaround: ROCm 5.7 returns "invalid argument" for
 * Vega GPUs on Windows.  Try the real function first; on failure, fall
 * back to querying totalGlobalMem from hipGetDeviceProperties.
 * ==================================================================== */
typedef int (*MemGetInfoFn)(size_t_shim* free, size_t_shim* total);
typedef int (*GetPropsFn)(void* prop, int deviceId);

__declspec(dllexport) int hipMemGetInfo(size_t_shim* free, size_t_shim* total) {
    void* h;
    MemGetInfoFn pReal;
    int err;

    if (!free || !total) return 1;
    h = GetModuleHandleA("amdhip64.dll");
    if (!h) h = LoadLibraryA("amdhip64.dll");
    if (!h) { *free = 0; *total = 0; return 1; }

    /* Try the real hipMemGetInfo first */
    pReal = (MemGetInfoFn)GetProcAddress(h, "hipMemGetInfo");
    if (pReal) {
        err = pReal(free, total);
        if (err == 0) return 0; /* success */
    }

    /* Fallback: query device properties for totalGlobalMem */
    {
        GetPropsFn pProps = (GetPropsFn)GetProcAddress(h, "hipGetDeviceProperties");
        if (pProps) {
            /* ROCm 5.7 hipDeviceProp_t: totalGlobalMem is at offset 256 */
            char prop[800];
            size_t_shim totalMem;
            shim_zero(prop, sizeof(prop));
            err = pProps(prop, 0);
            if (err == 0) {
                shim_copy(&totalMem, prop + 256, sizeof(totalMem));
                *total = totalMem;
                *free  = (size_t_shim)(totalMem * 9 / 10); /* 90% free as estimate */
                return 0;
            }
        }
    }

    *free = 0; *total = 0;
    return 1;
}

/* Minimal DLL entry point (no CRT) */
int __stdcall DllMainCRTStartup(void* hinst, unsigned long reason, void* reserved) {
    (void)hinst; (void)reason; (void)reserved;
    return 1;
}
