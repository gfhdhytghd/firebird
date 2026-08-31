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
};

struct FileValidation {
    bool valid = false;
    uint32_t product = 0;
    std::string model;
    std::string error;
};

class EmulatorService {
public:
    static EmulatorService &Instance();
    ~EmulatorService();

    FileValidation ValidateFiles(const std::string &bootPath, const std::string &flashPath) const;
    FileValidation Configure(std::string bootPath, std::string flashPath, bool jitEnabled);
    bool Start(const std::string &snapshotPath, std::string &error);
    void Pause();
    void Resume();
    bool Stop(std::string &error);
    bool SaveSnapshot(const std::string &path, std::string &error);
    bool ValidateSnapshotForCurrentFiles(const std::string &path, std::string &error) const;
    void QueueKey(uint32_t keyId, bool pressed);
    void QueueTouchpad(float x, float y, bool contact, bool down);
    void ReleaseAllInputs();
    EmulatorStatus Status() const;
    void SetStatusNotifier(void (*notifier)());

    // Called only by the Firebird core thread through the platform frontend.
    void CoreTick();
    void SetSpeed(double speed);
    void AppendLog(const std::string &message);

private:
    EmulatorService() = default;
    EmulatorService(const EmulatorService &) = delete;
    EmulatorService &operator=(const EmulatorService &) = delete;

    enum class InputKind { Key, Touchpad, ReleaseAll };
    struct InputCommand {
        InputKind kind;
        uint32_t keyId = 0;
        bool pressed = false;
        float x = 0;
        float y = 0;
        bool contact = false;
        bool down = false;
    };

    void ThreadMain(std::string snapshotPath);
    void DrainInputLocked(std::deque<InputCommand> &commands);

    mutable std::mutex mutex_;
    std::condition_variable condition_;
    std::thread thread_;
    std::string bootPath_;
    std::string flashPath_;
    bool jitEnabled_ = true;
    bool configured_ = false;
    bool paused_ = false;
    bool stopRequested_ = false;
    std::deque<InputCommand> inputQueue_;
    std::array<bool, 88> pressedKeys_{};

    bool snapshotPending_ = false;
    bool snapshotFinished_ = false;
    bool snapshotSucceeded_ = false;
    std::string snapshotPath_;
    std::string snapshotError_;

    EmulatorStatus status_;
    std::chrono::steady_clock::time_point lastFrame_{};
    uint64_t frameCount_ = 0;
    uint64_t lastFpsFrameCount_ = 0;
    std::chrono::steady_clock::time_point lastFpsUpdate_{};
    void (*statusNotifier_)() = nullptr;
    std::chrono::steady_clock::time_point lastStatusNotification_{};
};
