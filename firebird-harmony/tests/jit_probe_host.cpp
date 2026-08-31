#include <cassert>
#include <iostream>

#include "../entry/src/main/cpp/platform/jit_probe.h"

int main()
{
    JitProbeResult result = RunJitProbe();
    assert(result.pageSize >= 4096);
#if defined(__aarch64__)
    assert(result.success);
    assert(result.returnValue == 42);
#else
    assert(!result.success);
    assert(result.error.find("AArch64") != std::string::npos);
#endif
    std::cout << "pageSize=" << result.pageSize << " success=" << result.success << '\n';
    return 0;
}
