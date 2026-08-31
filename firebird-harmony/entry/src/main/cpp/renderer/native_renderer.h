#pragma once

#include <array>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>

struct NativeWindow;
typedef struct NativeWindow OHNativeWindow;

class NativeRenderer {
public:
    static NativeRenderer &Instance();

    bool RegisterXComponent(void *env, void *exports);
    void SetSurface(OHNativeWindow *window, uint64_t width, uint64_t height);
    void ResizeSurface(OHNativeWindow *window, uint64_t width, uint64_t height);
    void DestroySurface(OHNativeWindow *window);
    void SubmitRgb565(const uint16_t *pixels);

private:
    NativeRenderer();
    ~NativeRenderer();
    void RenderLoop();
    void DrawFrame(OHNativeWindow *window, uint32_t width, uint32_t height,
                   const std::array<uint16_t, 320 * 240> &frame);

    std::mutex mutex_;
    std::condition_variable condition_;
    std::thread thread_;
    OHNativeWindow *window_ = nullptr;
    uint32_t width_ = 0;
    uint32_t height_ = 0;
    std::array<uint16_t, 320 * 240> frame_{};
    bool hasFrame_ = false;
    bool framePending_ = false;
    bool stopping_ = false;
};
