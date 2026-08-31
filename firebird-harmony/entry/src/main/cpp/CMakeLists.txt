cmake_minimum_required(VERSION 3.16)
project(firebird_harmony LANGUAGES C CXX ASM)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
get_filename_component(FIREBIRD_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." REALPATH)
set(CORE "${FIREBIRD_ROOT}/core")

add_library(firebird_harmony SHARED
    napi/napi_init.cpp
    emulator/emulator_service.cpp
    platform/harmony_frontend.cpp
    platform/jit_probe.cpp
    renderer/native_renderer.cpp
    snapshot/snapshot_format.cpp

    ${CORE}/asmcode.c
    ${CORE}/asmcode_aarch64.S
    ${CORE}/translate_aarch64.cpp
    ${CORE}/arm_interpreter.cpp
    ${CORE}/thumb_interpreter.cpp
    ${CORE}/coproc.cpp
    ${CORE}/cpu.cpp
    ${CORE}/emu.cpp
    ${CORE}/flash.cpp
    ${CORE}/fieldparser.cpp
    ${CORE}/gif.cpp
    ${CORE}/keypad.cpp
    ${CORE}/cx2.cpp
    ${CORE}/usb_cx2.cpp
    ${CORE}/usblink_cx2.cpp
    ${CORE}/usblink_queue.cpp
    ${CORE}/debug.cpp
    ${CORE}/armsnippets_loader.c
    ${CORE}/casplus.c
    ${CORE}/des.c
    ${CORE}/disasm.c
    ${CORE}/gdbstub.c
    ${CORE}/interrupt.c
    ${CORE}/lcd.c
    ${CORE}/link.c
    ${CORE}/mem.c
    ${CORE}/misc.c
    ${CORE}/mmu.c
    ${CORE}/schedule.c
    ${CORE}/serial.c
    ${CORE}/sha256.c
    ${CORE}/usb.c
    ${CORE}/usblink.c
    ${CORE}/os/os-harmony.cpp
)

target_include_directories(firebird_harmony PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CORE}
)
target_compile_definitions(firebird_harmony PRIVATE
    __OHOS__
    OHOS_PLATFORM
    STRICT_JIT_INIT
    FB_VERSION=1.6
)
target_compile_options(firebird_harmony PRIVATE
    -O2
    -Wall -Wextra -Wno-unused-parameter -Wa,--noexecstack
    "-ffile-prefix-map=${FIREBIRD_ROOT}=."
    "-fdebug-prefix-map=${FIREBIRD_ROOT}=."
    "-fmacro-prefix-map=${FIREBIRD_ROOT}=."
)
target_link_options(firebird_harmony PRIVATE -Wl,-Bsymbolic)

find_library(ACE_NAPI ace_napi.z)
find_library(ACE_NDK ace_ndk.z)
find_library(HILOG hilog_ndk.z)
find_library(NATIVE_WINDOW native_window)
find_library(ZLIB z)

target_link_libraries(firebird_harmony PUBLIC
    ${ACE_NAPI}
    ${ACE_NDK}
    ${HILOG}
    ${NATIVE_WINDOW}
    ${ZLIB}
)
