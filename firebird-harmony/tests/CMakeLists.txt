cmake_minimum_required(VERSION 3.16)
project(firebird_harmony_host_tests LANGUAGES C CXX)

enable_testing()
set(CMAKE_CXX_STANDARD 17)

add_executable(jit_probe_host
    jit_probe_host.cpp
    ../entry/src/main/cpp/platform/jit_probe.cpp
    ../../core/os/os-linux.c
)
target_include_directories(jit_probe_host PRIVATE ../../core)

# os-linux also owns the emulator address-cache helpers. The probe does not
# reference them, so discard unused sections before resolving their symbols.
target_compile_options(jit_probe_host PRIVATE -ffunction-sections -fdata-sections)
target_link_options(jit_probe_host PRIVATE -Wl,--gc-sections)
add_test(NAME jit_probe_host COMMAND jit_probe_host)
