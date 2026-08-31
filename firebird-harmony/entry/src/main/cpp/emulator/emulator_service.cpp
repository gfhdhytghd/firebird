#include "emulator_service.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <unistd.h>

#include "../platform/jit_probe.h"
#include "../renderer/native_renderer.h"
#include "../snapshot/snapshot_format.h"
#include "../../../../../../core/emu.h"
#include "../../../../../../core/flash.h"
#include "../../../../../../core/keypad.h"
#include "../../../../../../core/lcd.h"
#include "../../../../../../core/debug.h"
#include "../../../../../../core/translate.h"
#include "../../../../../../core/usblink_queue.h"

namespace {
void TransferProgress(int progress, void *opaque)
{
    static_cast<EmulatorService *>(opaque)->SetTransferProgress(progress);
}
}

EmulatorService &EmulatorService::Instance()
{
    static EmulatorService service;
    return service;
}

EmulatorService::~EmulatorService()
{
    std::string ignored;
    Stop(ignored);
}

FileValidation EmulatorService::ValidateFiles(const std::string &bootPath,
                                               const std::string &flashPath) const
{
    FileValidation result;
    std::error_code ec;
    const auto bootSize = std::filesystem::file_size(bootPath, ec);
    if (ec || bootSize != 0x80000) {
        result.error = "Boot ROM must be exactly 524288 bytes";
        return result;
    }
    const auto flashSize = std::filesystem::file_size(flashPath, ec);
    if (ec || flashSize != 132u * 1024u * 1024u) {
        result.error = "CX II flash image must be exactly 138412032 bytes";
        return result;
    }

    FILE *flash = std::fopen(flashPath.c_str(), "rb");
    if (!flash) {
        result.error = "Flash image cannot be opened";
        return result;
    }
    result.model = flash_read_type(flash, false);
    std::fclose(flash);
    if (result.model == "CX II CAS")
        result.product = 0x1C0;
    else if (result.model == "CX II")
        result.product = 0x1D0;
    else {
        result.error = "Only CX II CAS and CX II flash images are supported; detected: " + result.model;
        return result;
    }
    if (access(flashPath.c_str(), R_OK | W_OK) != 0) {
        result.error = "Flash image must be readable and writable inside the app sandbox";
        return result;
    }
    result.valid = true;
    return result;
}

FileValidation EmulatorService::Configure(std::string bootPath, std::string flashPath,
                                          bool jitEnabled)
{
    FileValidation validation = ValidateFiles(bootPath, flashPath);
    std::unique_lock<std::mutex> lock(mutex_);
    if (thread_.joinable() && status_.state != "stopped" && status_.state != "error") {
        validation.valid = false;
        validation.error = "Stop the emulator before changing boot, flash, or JIT configuration";
    }
    if (!validation.valid) {
        status_.error = validation.error;
        status_.state = "error";
        auto notifier = statusNotifier_;
        lock.unlock();
        if (notifier) notifier();
        return validation;
    }
    bootPath_ = std::move(bootPath);
    flashPath_ = std::move(flashPath);
    jitEnabled_ = jitEnabled;
    configured_ = true;
    status_.product = validation.product;
    status_.model = validation.model;
    status_.jitRequested = jitEnabled;
    status_.error.clear();
    status_.state = "stopped";
    auto notifier = statusNotifier_;
    lock.unlock();
    if (notifier) notifier();
    return validation;
}

JitProbeResult EmulatorService::ProbeJit()
{
    JitProbeResult result = RunJitProbe();
    void (*notifier)() = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        status_.jitProbePassed = result.success;
        if (!result.success) {
            status_.state = "error";
            status_.error = result.error;
        }
        notifier = statusNotifier_;
    }
    if (notifier)
        notifier();
    return result;
}

bool EmulatorService::Start(const std::string &snapshotPath, std::string &error)
{
    std::unique_lock<std::mutex> lock(mutex_);
    if (!configured_) {
        error = "Boot ROM and flash must be configured first";
        return false;
    }
    if (thread_.joinable()) {
        if (status_.state != "stopped" && status_.state != "error") {
            error = "Emulator is already active";
            return false;
        }
        lock.unlock();
        thread_.join();
        lock.lock();
    }
    std::string coreSnapshot = snapshotPath;
    const std::string configuredFlash = flashPath_;
    if (!snapshotPath.empty()) {
        lock.unlock();
        if (!ValidateSnapshotForCurrentFiles(snapshotPath, error))
            return false;
        SnapshotInfo info = InspectSnapshot(snapshotPath);
        if (info.embeddedFlash && !RestoreEmbeddedFlash(snapshotPath, configuredFlash, error))
            return false;
        if (info.harmonyFormat) {
            coreSnapshot = snapshotPath + ".core.resume.tmp";
            if (!UnwrapHarmonySnapshot(snapshotPath, coreSnapshot, error))
                return false;
        }
        lock.lock();
    }
    if (jitEnabled_) {
        JitProbeResult probe = RunJitProbe();
        status_.jitProbePassed = probe.success;
        if (!probe.success) {
            status_.state = "error";
            status_.error = probe.error;
            error = probe.error;
            auto notifier = statusNotifier_;
            lock.unlock();
            if (notifier) notifier();
            return false;
        }
    } else {
        status_.jitProbePassed = false;
    }
    stopRequested_ = false;
    paused_ = false;
    startupFinished_ = false;
    startupSucceeded_ = false;
    status_.state = "starting";
    status_.error.clear();
    thread_ = std::thread(&EmulatorService::ThreadMain, this, coreSnapshot);
    condition_.wait(lock, [this] { return startupFinished_; });
    if (startupSucceeded_)
        return true;
    error = status_.error.empty() ? "Firebird core startup failed" : status_.error;
    lock.unlock();
    thread_.join();
    return false;
}

void EmulatorService::Pause()
{
    void (*notifier)() = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        paused_ = true;
        if (status_.state == "running")
            status_.state = "paused";
        notifier = statusNotifier_;
    }
    if (notifier) notifier();
}

void EmulatorService::Resume()
{
    void (*notifier)() = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        paused_ = false;
        if (status_.state == "paused")
            status_.state = "running";
        notifier = statusNotifier_;
    }
    condition_.notify_all();
    if (notifier) notifier();
}

void EmulatorService::QueueFileTransfer(std::string localPath, std::string remotePath)
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        InputCommand command;
        command.kind = InputKind::FileTransfer;
        command.localPath = std::move(localPath);
        command.remotePath = std::move(remotePath);
        inputQueue_.push_back(std::move(command));
        status_.transferProgress = 0;
    }
    condition_.notify_all();
}

void EmulatorService::QueueExitPressToTest()
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        InputCommand command;
        command.kind = InputKind::ExitPressToTest;
        inputQueue_.push_back(std::move(command));
        status_.transferProgress = 0;
    }
    condition_.notify_all();
}

bool EmulatorService::ConfigureDebugger(uint32_t gdbPort, uint32_t remotePort,
                                        bool debugOnStartValue, bool debugOnWarnValue,
                                        bool printOnWarnValue, std::string &error)
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (thread_.joinable() && status_.state != "stopped" && status_.state != "error") {
        error = "Stop the emulator before changing debugger listeners";
        return false;
    }
    gdbPort_ = gdbPort;
    remoteDebugPort_ = remotePort;
    debugOnStart_ = debugOnStartValue;
    debugOnWarn_ = debugOnWarnValue;
    printOnWarn_ = printOnWarnValue;
    return true;
}

void EmulatorService::QueueEnterDebugger()
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        InputCommand command;
        command.kind = InputKind::EnterDebugger;
        inputQueue_.push_back(std::move(command));
    }
    condition_.notify_all();
}

void EmulatorService::QueueDebuggerCommand(std::string commandText)
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        InputCommand command;
        command.kind = InputKind::DebugCommand;
        command.localPath = std::move(commandText);
        inputQueue_.push_back(std::move(command));
    }
    condition_.notify_all();
}

std::string EmulatorService::DebugLog() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    std::string result;
    for (const auto &line : debugLog_)
        result += line;
    return result;
}

bool EmulatorService::Stop(std::string &error)
{
    error.clear();
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!thread_.joinable())
            return true;
        stopRequested_ = true;
        paused_ = false;
    }
    condition_.notify_all();
    thread_.join();
    // A prior core/JIT/flash error is part of EmulatorStatus, not a failure to
    // stop the worker. Rejecting stop here made every recovery action that
    // begins with stop() (profile switching, image replacement, JIT changes)
    // unusable after the emulator entered the error state.
    return true;
}

bool EmulatorService::SaveSnapshot(const std::string &path, std::string &error)
{
    std::unique_lock<std::mutex> lock(mutex_);
    if (!thread_.joinable() || (status_.state != "running" && status_.state != "paused")) {
        error = "Emulator is not running";
        return false;
    }
    snapshotPending_ = true;
    snapshotFinished_ = false;
    snapshotPath_ = path + ".core.tmp";
    condition_.notify_all();
    condition_.wait(lock, [this] { return snapshotFinished_ || stopRequested_; });
    if (!snapshotSucceeded_) {
        error = snapshotError_;
        return false;
    }
    const uint32_t currentProduct = status_.product;
    const std::string boot = bootPath_;
    const std::string flash = flashPath_;
    const std::string corePath = snapshotPath_;
    lock.unlock();
    const bool wrapped = WrapHarmonySnapshot(corePath, path, currentProduct, boot, flash, error);
    std::error_code ec;
    std::filesystem::remove(corePath, ec);
    return wrapped;
}

bool EmulatorService::ValidateSnapshotForCurrentFiles(const std::string &path, std::string &error) const
{
    SnapshotInfo info = InspectSnapshot(path);
    if (!info.valid) {
        error = info.error;
        return false;
    }
    if (!info.harmonyFormat)
        return true;

    const std::string validationPayload = path + ".core.validate.tmp";
    if (!UnwrapHarmonySnapshot(path, validationPayload, error))
        return false;
    SnapshotInfo payloadInfo = InspectSnapshot(validationPayload);
    std::error_code removeError;
    std::filesystem::remove(validationPayload, removeError);
    if (!payloadInfo.valid || payloadInfo.harmonyFormat) {
        error = payloadInfo.error.empty() ? "Harmony snapshot contains an invalid core payload" :
                                            payloadInfo.error;
        return false;
    }

    std::string boot;
    std::string flash;
    uint32_t currentProduct = 0;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        boot = bootPath_;
        flash = flashPath_;
        currentProduct = status_.product;
    }
    if (info.product != currentProduct) {
        error = "Snapshot model does not match the configured flash image";
        return false;
    }
    std::string fingerprintError;
    const uint64_t bootFingerprint = FingerprintFile(boot, fingerprintError);
    const uint64_t flashFingerprint = info.embeddedFlash ? info.flashFingerprint :
                                      FingerprintFile(flash, fingerprintError);
    if (!fingerprintError.empty()) {
        error = fingerprintError;
        return false;
    }
    if (info.embeddedFlash && !ValidateEmbeddedFlash(path, fingerprintError)) {
        error = fingerprintError;
        return false;
    }
    if (bootFingerprint != info.bootFingerprint || flashFingerprint != info.flashFingerprint) {
        error = "Snapshot boot/flash fingerprints do not match the configured files";
        return false;
    }
    return true;
}

void EmulatorService::QueueKey(uint32_t keyId, bool pressed)
{
    if (keyId >= pressedKeys_.size())
        return;
    std::lock_guard<std::mutex> lock(mutex_);
    InputCommand command;
    command.kind = InputKind::Key;
    command.keyId = keyId;
    command.pressed = pressed;
    inputQueue_.push_back(std::move(command));
    condition_.notify_all();
}

void EmulatorService::QueueTouchpad(float x, float y, bool contact, bool down)
{
    InputCommand command;
    command.kind = InputKind::Touchpad;
    command.x = std::clamp(x, 0.0f, 1.0f);
    command.y = std::clamp(y, 0.0f, 1.0f);
    command.contact = contact;
    command.down = down;
    std::lock_guard<std::mutex> lock(mutex_);
    inputQueue_.push_back(std::move(command));
    condition_.notify_all();
}

void EmulatorService::QueueSpeedLimit(double limit)
{
    InputCommand command;
    command.kind = InputKind::SpeedLimit;
    command.speedLimit = limit == 2.0 ? 2.0 : (limit <= 0.0 ? 0.0 : 1.0);
    std::lock_guard<std::mutex> lock(mutex_);
    speedLimit_ = command.speedLimit;
    inputQueue_.push_back(command);
    condition_.notify_all();
}

void EmulatorService::ReleaseAllInputs()
{
    std::lock_guard<std::mutex> lock(mutex_);
    InputCommand command;
    command.kind = InputKind::ReleaseAll;
    inputQueue_.push_back(std::move(command));
    condition_.notify_all();
}

EmulatorStatus EmulatorService::Status() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return status_;
}

void EmulatorService::SetStatusNotifier(void (*notifier)())
{
    std::lock_guard<std::mutex> lock(mutex_);
    statusNotifier_ = notifier;
}

void EmulatorService::CoreTick()
{
    std::deque<InputCommand> commands;
    std::unique_lock<std::mutex> lock(mutex_);
    status_.translatedBlocks = jit_translated_blocks;
    status_.jitExecutionEntries = jit_execution_entries;
    if (stopRequested_)
        exiting = true;
    inputQueue_.swap(commands);

    std::array<bool, 88> newlyPressed {};
    std::array<bool, 88> deferredRelease {};
    for (const auto &command : commands) {
        if (command.kind == InputKind::Key) {
            if (command.pressed) {
                // A later DOWN in the same batch means the final state is held.
                deferredRelease[command.keyId] = false;
            }
            if (pressedKeys_[command.keyId] != command.pressed) {
                // NAPI can enqueue DOWN and UP between two 100 Hz core ticks.
                // Keep a newly pressed key down until the next tick so the
                // emulated keypad/PMU always observes even a very quick tap.
                if (!command.pressed && newlyPressed[command.keyId]) {
                    deferredRelease[command.keyId] = true;
                    continue;
                }
                pressedKeys_[command.keyId] = command.pressed;
                keypad_set_key(command.keyId / KEYPAD_COLS, command.keyId % KEYPAD_COLS,
                               command.pressed);
                newlyPressed[command.keyId] = command.pressed;
            }
        } else if (command.kind == InputKind::Touchpad) {
            touchpad_set_state(command.x, command.y, command.contact, command.down);
        } else if (command.kind == InputKind::SpeedLimit) {
            emu_set_speed_limit(command.speedLimit);
        } else if (command.kind == InputKind::FileTransfer) {
            usblink_queue_put_file(command.localPath, command.remotePath, TransferProgress, this);
        } else if (command.kind == InputKind::ExitPressToTest) {
            usblink_queue_new_dir("/Press-to-Test", nullptr, nullptr);
            usblink_queue_put_file(std::string(), "/Press-to-Test/Exit Test Mode.tns",
                                   TransferProgress, this);
        } else if (command.kind == InputKind::EnterDebugger) {
            lock.unlock();
            debugger(DBG_USER, 0);
            lock.lock();
        } else if (command.kind == InputKind::DebugCommand) {
            lastDebuggerCommand_ = command.localPath;
            if (debugInputCallback_) {
                const debug_input_cb callback = debugInputCallback_;
                debugInputCallback_ = nullptr;
                status_.debuggerWaitingForInput = false;
                lock.unlock();
                callback(lastDebuggerCommand_.c_str());
                lock.lock();
            }
        } else {
            newlyPressed.fill(false);
            deferredRelease.fill(false);
            for (uint32_t key = 0; key < pressedKeys_.size(); ++key) {
                if (pressedKeys_[key])
                    keypad_set_key(key / KEYPAD_COLS, key % KEYPAD_COLS, false);
                pressedKeys_[key] = false;
            }
            touchpad_set_state(0.5f, 0.5f, false, false);
        }
    }
    for (uint32_t key = 0; key < deferredRelease.size(); ++key) {
        if (deferredRelease[key]) {
            InputCommand release;
            release.kind = InputKind::Key;
            release.keyId = key;
            release.pressed = false;
            inputQueue_.push_back(std::move(release));
        }
    }

    if (snapshotPending_) {
        const std::string path = snapshotPath_;
        snapshotPending_ = false;
        lock.unlock();
        const bool success = emu_suspend(path.c_str());
        lock.lock();
        snapshotSucceeded_ = success;
        snapshotError_ = success ? "" : "Core snapshot write failed";
        snapshotFinished_ = true;
        condition_.notify_all();
    }

    if (paused_ && !stopRequested_)
        condition_.wait(lock, [this] { return !paused_ || stopRequested_ || snapshotPending_ || !inputQueue_.empty(); });

    const auto now = std::chrono::steady_clock::now();
    if (lastFpsUpdate_.time_since_epoch().count() == 0) {
        lastFpsUpdate_ = now;
        lastFpsFrameCount_ = frameCount_;
    } else if (now - lastFpsUpdate_ >= std::chrono::seconds(1)) {
        const double seconds = std::chrono::duration<double>(now - lastFpsUpdate_).count();
        status_.fps = static_cast<double>(frameCount_ - lastFpsFrameCount_) / seconds;
        lastFpsUpdate_ = now;
        lastFpsFrameCount_ = frameCount_;
    }
    if (statusNotifier_ && (lastStatusNotification_.time_since_epoch().count() == 0 ||
                            now - lastStatusNotification_ >= std::chrono::milliseconds(250))) {
        auto notifier = statusNotifier_;
        lastStatusNotification_ = now;
        lock.unlock();
        notifier();
        lock.lock();
    }
    const bool sleeping = (cpu_events & EVENT_SLEEP) != 0;
    if (sleeping && !displayBlanked_) {
        displayBlanked_ = true;
        lastFrame_ = now;
        lock.unlock();
        lcdFrame_.fill(0);
        NativeRenderer::Instance().SubmitRgb565(lcdFrame_.data());
        lock.lock();
        ++frameCount_;
    } else if (!sleeping &&
               (lastFrame_.time_since_epoch().count() == 0 ||
                now - lastFrame_ >= std::chrono::milliseconds(33))) {
        displayBlanked_ = false;
        lastFrame_ = now;
        lock.unlock();
        lcd_cx_draw_frame(lcdFrame_.data());
        NativeRenderer::Instance().SubmitRgb565(lcdFrame_.data());
        lock.lock();
        ++frameCount_;
    }
}

void EmulatorService::SetSpeed(double speed)
{
    std::lock_guard<std::mutex> lock(mutex_);
    status_.speed = speed;
}

void EmulatorService::AppendLog(const std::string &message)
{
    std::lock_guard<std::mutex> lock(mutex_);
    debugLog_.push_back(message);
    while (debugLog_.size() > 240)
        debugLog_.pop_front();
    if (message.find("Error") != std::string::npos)
        status_.error = message;
}

void EmulatorService::SetDebuggerActive(bool active)
{
    void (*notifier)() = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        status_.debuggerActive = active;
        if (!active) {
            status_.debuggerWaitingForInput = false;
            debugInputCallback_ = nullptr;
        }
        notifier = statusNotifier_;
    }
    if (notifier) notifier();
}

void EmulatorService::SetDebuggerInputCallback(debug_input_cb callback)
{
    void (*notifier)() = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        debugInputCallback_ = callback;
        status_.debuggerWaitingForInput = callback != nullptr;
        notifier = statusNotifier_;
    }
    if (notifier) notifier();
}

void EmulatorService::SetUsbLinkConnected(bool connected)
{
    void (*notifier)() = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        status_.usbLinkConnected = connected;
        notifier = statusNotifier_;
    }
    if (notifier) notifier();
}

void EmulatorService::SetTransferProgress(int progress)
{
    void (*notifier)() = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        status_.transferProgress = progress;
        notifier = statusNotifier_;
    }
    if (notifier) notifier();
}

void EmulatorService::ThreadMain(std::string snapshotPath)
{
    std::string boot;
    std::string flash;
    bool jit = true;
    double speedLimit = 1.0;
    uint32_t gdbPort = 0;
    uint32_t remoteDebugPort = 0;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        boot = bootPath_;
        flash = flashPath_;
        jit = jitEnabled_;
        speedLimit = speedLimit_;
        gdbPort = gdbPort_;
        remoteDebugPort = remoteDebugPort_;
        debug_on_start = debugOnStart_;
        debug_on_warn = debugOnWarn_;
        print_on_warn = printOnWarn_;
    }
    path_boot1 = boot;
    path_flash = flash;
    do_translate = jit;
    emu_set_speed_limit(speedLimit);
    snapshot_use_current_paths = true;
    jit_translated_blocks = 0;
    jit_execution_entries = 0;

    const bool started = emu_start(gdbPort, remoteDebugPort,
                                   snapshotPath.empty() ? nullptr : snapshotPath.c_str());
    constexpr const char *temporarySuffix = ".core.resume.tmp";
    if (snapshotPath.size() >= std::strlen(temporarySuffix) &&
        snapshotPath.compare(snapshotPath.size() - std::strlen(temporarySuffix),
                             std::strlen(temporarySuffix), temporarySuffix) == 0) {
        std::error_code ec;
        std::filesystem::remove(snapshotPath, ec);
    }
    void (*startupNotifier)() = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!started) {
            status_.state = "error";
            if (status_.error.empty())
                status_.error = "Firebird core startup failed";
        } else {
            status_.state = "running";
        }
        status_.jitInitialized = started && jit && translate_is_initialized();
        startupSucceeded_ = started;
        startupFinished_ = true;
        condition_.notify_all();
        startupNotifier = statusNotifier_;
    }
    if (startupNotifier) startupNotifier();
    if (started) {
        emu_loop(false);
        ReleaseAllInputs();
        CoreTick();
        if (!flash_save_changes()) {
            std::lock_guard<std::mutex> lock(mutex_);
            status_.error = "Could not persist modified flash blocks";
        }
        emu_cleanup();
    }
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (status_.state != "error")
            status_.state = "stopped";
        snapshotFinished_ = true;
        snapshotSucceeded_ = false;
        condition_.notify_all();
    }
}
