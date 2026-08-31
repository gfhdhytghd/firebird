#pragma once

#include <cstddef>
#include <string>

struct JitProbeResult {
    bool success = false;
    size_t pageSize = 0;
    int returnValue = 0;
    int errorNumber = 0;
    std::string error;
};

JitProbeResult RunJitProbe();
