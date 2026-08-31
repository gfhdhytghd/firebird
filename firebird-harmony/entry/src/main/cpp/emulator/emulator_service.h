#pragma once

#include <array>
#include <atomic>
#include <condition_variable>
#include <chrono>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <thread>

#include "../../../../../../core/emu.h"

struct EmulatorStatus {
    std::string state = "stopped";
    std::string error;
    double speed = 0.0;
    double fps = 0.0;
    bool jitRequested = true;
    bool jitProbePassed = false;
    bool jitInitialized = false;
    uint64_t translatedBlocks = 0;
    uint64_t jitExecutionEntries = 0;
    uint32_t product = 0;
    std::string model;
    bool usbLinkConnected = false;
    int transferProgress = -1;
    bool debuggerActive = false;
    bool debuggerWaitingForInput = false;
};

struct FileValidation {
    bool valid = false;
    uint32_t product = 0;
    std::string model;
    std::string error;
};

struct JitProbeResult;

class EmulatorService {
public:
    static EmulatorService &Instance();
    ~EmulatorService();

    FileValidation ValidateFiles(const std::string &bootPath, const std::string &flashPath) const;
    FileValidation Configure(std::string bootPath, std::string flashPath, bool jitEnabled);
    JitProbeResult ProbeJit();
    bool Start(const std::string &snapshotPath, std::string &error);
    void Pause();
    void Resume();
    bool Stop(std::string &error);
    bool SaveSnapshot(const std::string &path, std::string &error);
    bool ValidateSnapshotForCurrentFiles(const std::string &path, std::string &error) const;
    void QueueKey(uint32_t keyId, bool pressed);
    void QueueTouchpad(float x, float y, bool contact, bool down);
    void QueueSpeedLimit(double limit);
    void QueueFileTransfer(std::string localPath, std::string remotePath);
    void QueueExitPressToTest();
    bool ConfigureDebugger(uint32_t gdbPort, uint32_t remotePort, bool debugOnStart,
                           bool debugOnWarn, bool printOnWarn, std::string &error);
    void QueueEnterDebugger();
    void QueueDebuggerCommand(std::string command);
    std::string DebugLog() const;
    void ReleaseAllInputs();
    EmulatorStatus Status() const;
    void SetStatusNotifier(void (*notifier)());

    // Called only by the Firebird core thread through the platform frontend.
    void CoreTick();
    void SetSpeed(double speed);
    void AppendLog(const std::string &message);
    void SetUsbLinkConnected(bool connected);
    void SetTransferProgress(int progress);
    void SetDebuggerActive(bool active);
    void SetDebuggerInputCallback(debug_input_cb callback);

private:
    EmulatorService() = default;
    EmulatorService(const EmulatorService &) = delete;
    EmulatorService &operator=(const EmulatorService &) = delete;

    enum class InputKind { Key, Touchpad, SpeedLimit, FileTransfer, ExitPressToTest,
                           EnterDebugger, DebugCommand, ReleaseAll };
    struct InputCommand {
        InputKind kind;
        uint32_t keyId = 0;
        bool pressed = false;
        float x = 0;
        float y = 0;
        bool contact = false;
        bool down = false;
        double speedLimit = 1.0;
        std::string localPath;
        std::string remotePath;
    };

    void ThreadMain(std::string snapshotPath);
    void DrainInputLocked(std::deque<InputCommand> &commands);

    mutable std::mutex mutex_;
    std::condition_variable condition_;
    std::thread thread_;
    std::string bootPath_;
    std::string flashPath_;
    bool jitEnabled_ = true;
    double speedLimit_ = 1.0;
    bool configured_ = false;
    uint32_t gdbPort_ = 0;
    uint32_t remoteDebugPort_ = 0;
    bool debugOnStart_ = false;
    bool debugOnWarn_ = false;
    bool printOnWarn_ = true;
    bool paused_ = false;
    bool stopRequested_ = false;
    bool startupFinished_ = false;
    bool startupSucceeded_ = false;
    std::deque<InputCommand> inputQueue_;
    std::array<bool, 88> pressedKeys_{};
    debug_input_cb debugInputCallback_ = nullptr;
    std::string lastDebuggerCommand_;
    std::deque<std::string> debugLog_;

    bool snapshotPending_ = false;
    bool snapshotFinished_ = false;
    bool snapshotSucceeded_ = false;
    std::string snapshotPath_;
    std::string snapshotError_;

    EmulatorStatus status_;
    std::chrono::steady_clock::time_point lastFrame_{};
    uint64_t frameCount_ = 0;
    uint64_t lastFpsFrameCount_ = 0;
    std::array<uint16_t, 320 * 240> lcdFrame_{};
    bool displayBlanked_ = false;
    std::chrono::steady_clock::time_point lastFpsUpdate_{};
    void (*statusNotifier_)() = nullptr;
    std::chrono::steady_clock::time_point lastStatusNotification_{};
};
