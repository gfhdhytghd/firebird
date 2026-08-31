#include <cstdarg>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>

#include <hilog/log.h>

#include "../emulator/emulator_service.h"
#include "../../../../../../core/emu.h"

namespace {
std::string Format(const char *format, va_list arguments)
{
    va_list copy;
    va_copy(copy, arguments);
    const int length = std::vsnprintf(nullptr, 0, format, copy);
    va_end(copy);
    if (length <= 0)
        return {};
    std::string output(static_cast<size_t>(length), '\0');
    std::vsnprintf(output.data(), output.size() + 1, format, arguments);
    return output;
}
}

void gui_do_stuff(bool) { EmulatorService::Instance().CoreTick(); }
void do_stuff(int) {}

void gui_debug_vprintf(const char *format, va_list arguments)
{
    std::string message = Format(format, arguments);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0x4642, "FirebirdCore", "%{public}s", message.c_str());
    EmulatorService::Instance().AppendLog(message);
}

void gui_debug_printf(const char *format, ...)
{
    va_list arguments;
    va_start(arguments, format);
    gui_debug_vprintf(format, arguments);
    va_end(arguments);
}

void gui_status_printf(const char *format, ...)
{
    va_list arguments;
    va_start(arguments, format);
    gui_debug_vprintf(format, arguments);
    va_end(arguments);
}

void gui_perror(const char *message) { gui_debug_printf("%s: %s", message, std::strerror(errno)); }
void gui_debugger_entered_or_left(bool) {}
void gui_debugger_request_input(debug_input_cb callback) { if (callback) callback(""); }
void gui_putchar(char) {}
int gui_getchar() { return -1; }
void gui_set_busy(bool) {}
void gui_show_speed(double speed) { EmulatorService::Instance().SetSpeed(speed); }
void gui_usblink_changed(bool) {}
void throttle_timer_off() {}
void throttle_timer_on() {}
void throttle_timer_wait(unsigned int usec) { std::this_thread::sleep_for(std::chrono::microseconds(usec)); }
