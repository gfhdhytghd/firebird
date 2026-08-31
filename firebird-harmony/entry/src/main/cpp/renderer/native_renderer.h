#pragma once

#include <array>
#include <cstdint>
#include <mutex>

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
    NativeRenderer() = default;
    void DrawLocked();

    std::mutex mutex_;
    OHNativeWindow *window_ = nullptr;
    uint32_t width_ = 0;
    uint32_t height_ = 0;
    std::array<uint16_t, 320 * 240> frame_{};
    bool hasFrame_ = false;
};
