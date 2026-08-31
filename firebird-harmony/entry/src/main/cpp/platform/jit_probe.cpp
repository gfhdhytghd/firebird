#include "jit_probe.h"

#include <cerrno>
#include <cstdint>
#include <cstring>

#if defined(__OHOS__)
#include <hilog/log.h>
#define JIT_LOG(level, format, ...) \
    OH_LOG_Print(LOG_APP, level, 0x4642, "FirebirdJit", format, ##__VA_ARGS__)
#else
#define JIT_LOG(...) ((void)0)
#endif

#include "../../../../../../core/os/os.h"

JitProbeResult RunJitProbe()
{
    JitProbeResult result;
    result.pageSize = os_page_size();
    JIT_LOG(LOG_INFO, "probe start: pageSize=%{public}zu", result.pageSize);
    void *page = os_alloc_executable(result.pageSize);
    if (!page) {
        result.errorNumber = errno;
        result.error = std::string("RW code allocation failed: ") + std::strerror(errno);
        JIT_LOG(LOG_ERROR, "RW allocation failed: errno=%{public}d", result.errorNumber);
        return result;
    }
    JIT_LOG(LOG_INFO, "RW allocation passed");

#if defined(__aarch64__)
    // mov w0, #42; ret
    const uint32_t code[] = {0x52800540u, 0xD65F03C0u};
    std::memcpy(page, code, sizeof(code));
    os_flush_instruction_cache(page, static_cast<char *>(page) + sizeof(code));
    JIT_LOG(LOG_INFO, "instruction cache flushed");
    if (!os_executable_set_executable(page, result.pageSize)) {
        result.errorNumber = errno;
        result.error = std::string("RX transition failed: ") + std::strerror(errno);
        JIT_LOG(LOG_ERROR, "RX transition failed: errno=%{public}d", result.errorNumber);
        os_free(page, result.pageSize);
        return result;
    }
    JIT_LOG(LOG_INFO, "RX transition passed");

    using ProbeFunction = int (*)();
    result.returnValue = reinterpret_cast<ProbeFunction>(page)();
    result.success = result.returnValue == 42;
    JIT_LOG(result.success ? LOG_INFO : LOG_ERROR,
            "execution returned %{public}d", result.returnValue);
    if (!result.success)
        result.error = "Generated AArch64 function returned an unexpected value";
#else
    result.error = "JIT execution probe requires an AArch64 target";
#endif

    // The page is unmapped from RX. It is never made RWX.
    os_free(page, result.pageSize);
    return result;
}
