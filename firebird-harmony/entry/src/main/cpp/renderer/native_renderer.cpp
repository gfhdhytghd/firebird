#include "native_renderer.h"

#include <algorithm>
#include <cerrno>
#include <cstring>

#include <ace/xcomponent/native_interface_xcomponent.h>
#include <hilog/log.h>
#include <napi/native_api.h>
#include <native_buffer/native_buffer.h>
#include <native_window/external_window.h>
#include <native_window/graphic_error_code.h>
#include <poll.h>
#include <sys/mman.h>
#include <unistd.h>

#include "../emulator/emulator_service.h"

namespace {
void OnSurfaceCreated(OH_NativeXComponent *component, void *window)
{
    uint64_t width = 0;
    uint64_t height = 0;
    if (OH_NativeXComponent_GetXComponentSize(component, window, &width, &height) ==
        OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        NativeRenderer::Instance().SetSurface(static_cast<OHNativeWindow *>(window), width, height);
    }
}

void OnSurfaceChanged(OH_NativeXComponent *component, void *window)
{
    uint64_t width = 0;
    uint64_t height = 0;
    if (OH_NativeXComponent_GetXComponentSize(component, window, &width, &height) ==
        OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        NativeRenderer::Instance().ResizeSurface(static_cast<OHNativeWindow *>(window), width, height);
    }
}

void OnSurfaceDestroyed(OH_NativeXComponent *, void *window)
{
    EmulatorService::Instance().ReleaseAllInputs();
    NativeRenderer::Instance().DestroySurface(static_cast<OHNativeWindow *>(window));
}

OH_NativeXComponent_Callback g_callback {
    .OnSurfaceCreated = OnSurfaceCreated,
    .OnSurfaceChanged = OnSurfaceChanged,
    .OnSurfaceDestroyed = OnSurfaceDestroyed,
    .DispatchTouchEvent = nullptr,
};
}

NativeRenderer &NativeRenderer::Instance()
{
    static NativeRenderer renderer;
    return renderer;
}

bool NativeRenderer::RegisterXComponent(void *opaqueEnv, void *opaqueExports)
{
    auto env = static_cast<napi_env>(opaqueEnv);
    auto exports = static_cast<napi_value>(opaqueExports);
    napi_value instance = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &instance) != napi_ok)
        return false;
    OH_NativeXComponent *component = nullptr;
    if (napi_unwrap(env, instance, reinterpret_cast<void **>(&component)) != napi_ok || !component)
        return false;
    return OH_NativeXComponent_RegisterCallback(component, &g_callback) ==
           OH_NATIVEXCOMPONENT_RESULT_SUCCESS;
}

void NativeRenderer::SetSurface(OHNativeWindow *window, uint64_t width, uint64_t height)
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (window_ != window) {
        if (window_)
            OH_NativeWindow_NativeObjectUnreference(window_);
        window_ = window;
        if (window_)
            OH_NativeWindow_NativeObjectReference(window_);
    }
    width_ = static_cast<uint32_t>(width);
    height_ = static_cast<uint32_t>(height);
    if (window_) {
        OH_NativeWindow_NativeWindowHandleOpt(window_, SET_BUFFER_GEOMETRY,
                                               static_cast<int32_t>(width_),
                                               static_cast<int32_t>(height_));
        OH_NativeWindow_NativeWindowHandleOpt(window_, SET_FORMAT,
                                               NATIVEBUFFER_PIXEL_FMT_RGBA_8888);
        DrawLocked();
    }
}

void NativeRenderer::ResizeSurface(OHNativeWindow *window, uint64_t width, uint64_t height)
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (window_ != window)
        return;
    width_ = static_cast<uint32_t>(width);
    height_ = static_cast<uint32_t>(height);
    OH_NativeWindow_NativeWindowHandleOpt(window_, SET_BUFFER_GEOMETRY,
                                           static_cast<int32_t>(width_),
                                           static_cast<int32_t>(height_));
    DrawLocked();
}

void NativeRenderer::DestroySurface(OHNativeWindow *window)
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (window_ != window)
        return;
    OH_NativeWindow_NativeObjectUnreference(window_);
    window_ = nullptr;
    width_ = height_ = 0;
}

void NativeRenderer::SubmitRgb565(const uint16_t *pixels)
{
    if (!pixels)
        return;
    std::lock_guard<std::mutex> lock(mutex_);
    std::copy_n(pixels, frame_.size(), frame_.begin());
    hasFrame_ = true;
    DrawLocked();
}

void NativeRenderer::DrawLocked()
{
    if (!window_ || !hasFrame_ || width_ == 0 || height_ == 0)
        return;

    OHNativeWindowBuffer *buffer = nullptr;
    int releaseFence = -1;
    if (OH_NativeWindow_NativeWindowRequestBuffer(window_, &buffer, &releaseFence) != NATIVE_ERROR_OK || !buffer)
        return;

    if (releaseFence >= 0) {
        pollfd descriptor {releaseFence, POLLIN, 0};
        int pollResult;
        do {
            pollResult = poll(&descriptor, 1, 3000);
        } while (pollResult < 0 && (errno == EINTR || errno == EAGAIN));
        close(releaseFence);
    }

    BufferHandle *handle = OH_NativeWindow_GetBufferHandleFromNative(buffer);
    if (!handle) {
        OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
        return;
    }
    void *mapping = mmap(handle->virAddr, handle->size, PROT_READ | PROT_WRITE,
                         MAP_SHARED, handle->fd, 0);
    if (mapping == MAP_FAILED) {
        OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
        return;
    }

    auto *output = static_cast<uint32_t *>(mapping);
    const uint32_t strideBytes = static_cast<uint32_t>(handle->stride);
    const uint32_t targetWidth = static_cast<uint32_t>(handle->width);
    const uint32_t targetHeight = static_cast<uint32_t>(handle->height);
    if (strideBytes < targetWidth * sizeof(uint32_t) ||
        static_cast<size_t>(strideBytes) * targetHeight > static_cast<size_t>(handle->size)) {
        munmap(mapping, handle->size);
        OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
        return;
    }
    const uint32_t stridePixels = strideBytes / sizeof(uint32_t);
    std::fill_n(output, static_cast<size_t>(handle->size) / sizeof(uint32_t), 0xFF000000u);

    const double scale = std::min(targetWidth / 320.0, targetHeight / 240.0);
    const uint32_t drawWidth = std::max(1u, static_cast<uint32_t>(320.0 * scale));
    const uint32_t drawHeight = std::max(1u, static_cast<uint32_t>(240.0 * scale));
    const uint32_t offsetX = (targetWidth - drawWidth) / 2;
    const uint32_t offsetY = (targetHeight - drawHeight) / 2;

    for (uint32_t y = 0; y < drawHeight; ++y) {
        const uint32_t sourceY = std::min(239u, y * 240u / drawHeight);
        uint32_t *row = output + (offsetY + y) * stridePixels + offsetX;
        for (uint32_t x = 0; x < drawWidth; ++x) {
            const uint16_t rgb565 = frame_[sourceY * 320u + std::min(319u, x * 320u / drawWidth)];
            const uint32_t r = ((rgb565 >> 11) & 0x1F) * 255 / 31;
            const uint32_t g = ((rgb565 >> 5) & 0x3F) * 255 / 63;
            const uint32_t b = (rgb565 & 0x1F) * 255 / 31;
            row[x] = 0xFF000000u | (b << 16) | (g << 8) | r;
        }
    }

    munmap(mapping, handle->size);
    Region::Rect fullSurface {0, 0, targetWidth, targetHeight};
    Region dirty {};
    dirty.rectNumber = 1;
    dirty.rects = &fullSurface;
    if (OH_NativeWindow_NativeWindowFlushBuffer(window_, buffer, -1, dirty) != NATIVE_ERROR_OK)
        OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
}
