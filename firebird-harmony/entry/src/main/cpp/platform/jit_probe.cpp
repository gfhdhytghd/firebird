#include "jit_probe.h"

#include <cerrno>
#include <cstdint>
#include <cstring>

#include "../../../../../../core/os/os.h"

JitProbeResult RunJitProbe()
{
    JitProbeResult result;
    result.pageSize = os_page_size();
    void *page = os_alloc_executable(result.pageSize);
    if (!page) {
        result.errorNumber = errno;
        result.error = std::string("RW code allocation failed: ") + std::strerror(errno);
        return result;
    }

#if defined(__aarch64__)
    // mov w0, #42; ret
    const uint32_t code[] = {0x52800540u, 0xD65F03C0u};
    std::memcpy(page, code, sizeof(code));
    os_flush_instruction_cache(page, static_cast<char *>(page) + sizeof(code));
    if (!os_executable_set_executable(page, result.pageSize)) {
        result.errorNumber = errno;
        result.error = std::string("RX transition failed: ") + std::strerror(errno);
        os_free(page, result.pageSize);
        return result;
    }

    using ProbeFunction = int (*)();
    result.returnValue = reinterpret_cast<ProbeFunction>(page)();
    result.success = result.returnValue == 42;
    if (!result.success)
        result.error = "Generated AArch64 function returned an unexpected value";
#else
    result.error = "JIT execution probe requires an AArch64 target";
#endif

    // The page is unmapped from RX. It is never made RWX.
    os_free(page, result.pageSize);
    return result;
}
