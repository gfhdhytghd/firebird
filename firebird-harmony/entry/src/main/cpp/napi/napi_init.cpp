#include <algorithm>
#include <filesystem>
#include <string>

#include <napi/native_api.h>

#include "../emulator/emulator_service.h"
#include "../platform/jit_probe.h"
#include "../renderer/native_renderer.h"
#include "../snapshot/snapshot_format.h"

namespace {
napi_threadsafe_function g_statusFunction = nullptr;

enum class AsyncOperation { Start, Stop, RestartCold, SaveSnapshot, LoadSnapshot };

struct AsyncContext {
    napi_env env = nullptr;
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
    AsyncOperation operation = AsyncOperation::Stop;
    std::string path;
    std::string error;
    bool success = false;
};
napi_value Undefined(napi_env env)
{
    napi_value value;
    napi_get_undefined(env, &value);
    return value;
}

napi_value String(napi_env env, const std::string &text)
{
    napi_value value;
    napi_create_string_utf8(env, text.c_str(), text.size(), &value);
    return value;
}

napi_value Boolean(napi_env env, bool input)
{
    napi_value value;
    napi_get_boolean(env, input, &value);
    return value;
}

napi_value Number(napi_env env, double input)
{
    napi_value value;
    napi_create_double(env, input, &value);
    return value;
}

void Set(napi_env env, napi_value object, const char *name, napi_value value)
{
    napi_set_named_property(env, object, name, value);
}

std::string GetString(napi_env env, napi_value value)
{
    size_t length = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &length);
    std::string result(length, '\0');
    napi_get_value_string_utf8(env, value, result.data(), result.size() + 1, &length);
    return result;
}

napi_value Resolved(napi_env env, napi_value value)
{
    napi_deferred deferred;
    napi_value promise;
    napi_create_promise(env, &deferred, &promise);
    napi_resolve_deferred(env, deferred, value);
    return promise;
}

napi_value Rejected(napi_env env, const std::string &message)
{
    napi_deferred deferred;
    napi_value promise;
    napi_create_promise(env, &deferred, &promise);
    napi_value errorMessage = String(env, message);
    napi_value error;
    napi_create_error(env, nullptr, errorMessage, &error);
    napi_reject_deferred(env, deferred, error);
    return promise;
}

void ExecuteAsync(napi_env, void *opaque)
{
    auto *context = static_cast<AsyncContext *>(opaque);
    auto &service = EmulatorService::Instance();
    switch (context->operation) {
    case AsyncOperation::Start:
        context->success = service.Start(context->path, context->error);
        break;
    case AsyncOperation::Stop:
        context->success = service.Stop(context->error);
        break;
    case AsyncOperation::RestartCold:
        service.Stop(context->error);
        context->error.clear();
        context->success = service.Start("", context->error);
        break;
    case AsyncOperation::SaveSnapshot:
        context->success = service.SaveSnapshot(context->path, context->error);
        break;
    case AsyncOperation::LoadSnapshot:
        context->success = service.ValidateSnapshotForCurrentFiles(context->path, context->error);
        if (context->success) {
            const EmulatorStatus before = service.Status();
            const bool needsRollback = before.state == "running" || before.state == "paused";
            const std::string rollback = context->path + ".rollback.tmp";
            if (needsRollback)
                context->success = service.SaveSnapshot(rollback, context->error);
            if (!context->success)
                break;
            service.Stop(context->error);
            context->error.clear();
            context->success = service.Start(context->path, context->error);
            if (!context->success && needsRollback) {
                const std::string loadError = context->error;
                context->error.clear();
                if (!service.Start(rollback, context->error)) {
                    context->error = loadError + "; rollback also failed: " + context->error;
                } else {
                    context->error = loadError;
                }
            }
            if (needsRollback) {
                std::error_code removeError;
                std::filesystem::remove(rollback, removeError);
            }
        }
        break;
    }
}

void CompleteAsync(napi_env env, napi_status status, void *opaque)
{
    auto *context = static_cast<AsyncContext *>(opaque);
    if (status == napi_ok && context->success) {
        napi_resolve_deferred(env, context->deferred, Undefined(env));
    } else {
        const std::string message = context->error.empty() ? "Native operation failed" : context->error;
        napi_value error;
        napi_create_error(env, nullptr, String(env, message), &error);
        napi_reject_deferred(env, context->deferred, error);
    }
    napi_delete_async_work(env, context->work);
    delete context;
}

napi_value QueueAsync(napi_env env, AsyncOperation operation, std::string path, const char *name)
{
    auto *context = new AsyncContext;
    context->env = env;
    context->operation = operation;
    context->path = std::move(path);
    napi_value promise;
    napi_create_promise(env, &context->deferred, &promise);
    napi_value resourceName = String(env, name);
    if (napi_create_async_work(env, nullptr, resourceName, ExecuteAsync, CompleteAsync,
                               context, &context->work) != napi_ok ||
        napi_queue_async_work(env, context->work) != napi_ok) {
        napi_value error;
        napi_create_error(env, nullptr, String(env, "Could not queue native operation"), &error);
        napi_reject_deferred(env, context->deferred, error);
        if (context->work) napi_delete_async_work(env, context->work);
        delete context;
    }
    return promise;
}

napi_value ValidationObject(napi_env env, const FileValidation &result)
{
    napi_value object;
    napi_create_object(env, &object);
    Set(env, object, "valid", Boolean(env, result.valid));
    Set(env, object, "product", Number(env, result.product));
    Set(env, object, "model", String(env, result.model));
    Set(env, object, "error", String(env, result.error));
    return object;
}

napi_value ProbeJit(napi_env env, napi_callback_info)
{
    JitProbeResult result = EmulatorService::Instance().ProbeJit();
    napi_value object;
    napi_create_object(env, &object);
    Set(env, object, "success", Boolean(env, result.success));
    Set(env, object, "pageSize", Number(env, result.pageSize));
    Set(env, object, "returnValue", Number(env, result.returnValue));
    Set(env, object, "error", String(env, result.error));
    return Resolved(env, object);
}

napi_value ValidateFiles(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 2)
        return Rejected(env, "validateFiles requires bootPath and flashPath");
    return Resolved(env, ValidationObject(env, EmulatorService::Instance().ValidateFiles(
        GetString(env, args[0]), GetString(env, args[1]))));
}

napi_value Configure(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 1)
        return Rejected(env, "configure requires one configuration object");
    napi_value bootValue;
    napi_value flashValue;
    napi_value jitValue;
    napi_get_named_property(env, args[0], "bootPath", &bootValue);
    napi_get_named_property(env, args[0], "flashPath", &flashValue);
    napi_get_named_property(env, args[0], "jitEnabled", &jitValue);
    bool jitEnabled = true;
    napi_get_value_bool(env, jitValue, &jitEnabled);
    FileValidation result = EmulatorService::Instance().Configure(
        GetString(env, bootValue), GetString(env, flashValue), jitEnabled);
    return Resolved(env, ValidationObject(env, result));
}

napi_value Start(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1)
        return Rejected(env, "start requires a mode");
    const std::string mode = GetString(env, args[0]);
    if (mode != "auto" && mode != "cold" && mode != "snapshot")
        return Rejected(env, "start mode must be auto, cold, or snapshot");
    std::string snapshot;
    if (argc > 1) {
        napi_valuetype type = napi_undefined;
        napi_typeof(env, args[1], &type);
        if (type == napi_string)
            snapshot = GetString(env, args[1]);
    }
    if (mode == "cold")
        snapshot.clear();
    if (mode == "snapshot" && snapshot.empty())
        return Rejected(env, "snapshot mode requires a snapshot path");
    return QueueAsync(env, AsyncOperation::Start, snapshot, "FirebirdStart");
}

napi_value Pause(napi_env env, napi_callback_info)
{
    EmulatorService::Instance().Pause();
    return Undefined(env);
}

napi_value Resume(napi_env env, napi_callback_info)
{
    EmulatorService::Instance().Resume();
    return Undefined(env);
}

napi_value Stop(napi_env env, napi_callback_info)
{
    return QueueAsync(env, AsyncOperation::Stop, "", "FirebirdStop");
}

napi_value RestartCold(napi_env env, napi_callback_info)
{
    return QueueAsync(env, AsyncOperation::RestartCold, "", "FirebirdRestart");
}

napi_value SaveSnapshot(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 1)
        return Rejected(env, "saveSnapshot requires a sandbox path");
    return QueueAsync(env, AsyncOperation::SaveSnapshot, GetString(env, args[0]), "FirebirdSaveSnapshot");
}

napi_value LoadSnapshot(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 1)
        return Rejected(env, "loadSnapshot requires a sandbox path");
    return QueueAsync(env, AsyncOperation::LoadSnapshot, GetString(env, args[0]), "FirebirdLoadSnapshot");
}

napi_value InspectSnapshotFile(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 1)
        return Rejected(env, "inspectSnapshot requires a sandbox path");
    SnapshotInfo result = InspectSnapshot(GetString(env, args[0]));
    napi_value object;
    napi_create_object(env, &object);
    Set(env, object, "valid", Boolean(env, result.valid));
    Set(env, object, "harmonyFormat", Boolean(env, result.harmonyFormat));
    Set(env, object, "version", Number(env, result.version));
    Set(env, object, "product", Number(env, result.product));
    Set(env, object, "error", String(env, result.error));
    return Resolved(env, object);
}

napi_value SetKeyState(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    uint32_t key = 0;
    bool pressed = false;
    if (argc == 2) {
        napi_get_value_uint32(env, args[0], &key);
        napi_get_value_bool(env, args[1], &pressed);
        EmulatorService::Instance().QueueKey(key, pressed);
    }
    return Undefined(env);
}

napi_value SetTouchpadState(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    double x = 0.5;
    double y = 0.5;
    bool contact = false;
    bool down = false;
    if (argc == 4) {
        napi_get_value_double(env, args[0], &x);
        napi_get_value_double(env, args[1], &y);
        napi_get_value_bool(env, args[2], &contact);
        napi_get_value_bool(env, args[3], &down);
        EmulatorService::Instance().QueueTouchpad(static_cast<float>(x), static_cast<float>(y), contact, down);
    }
    return Undefined(env);
}

napi_value ReleaseAllInputs(napi_env env, napi_callback_info)
{
    EmulatorService::Instance().ReleaseAllInputs();
    return Undefined(env);
}

napi_value SetSpeedLimit(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    double limit = 1.0;
    if (argc == 1 && napi_get_value_double(env, args[0], &limit) == napi_ok)
        EmulatorService::Instance().QueueSpeedLimit(limit);
    return Undefined(env);
}

napi_value SendFile(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 2) {
        napi_throw_type_error(env, nullptr, "sendFile requires a sandbox file and calculator path");
        return Undefined(env);
    }
    const std::string local = GetString(env, args[0]);
    const std::string remote = GetString(env, args[1]);
    std::error_code error;
    if (!std::filesystem::is_regular_file(local, error)) {
        napi_throw_error(env, nullptr, "Transfer source is not a readable sandbox file");
        return Undefined(env);
    }
    if (remote.empty() || remote.front() != '/' || remote.find("..") != std::string::npos) {
        napi_throw_error(env, nullptr, "Calculator destination must be an absolute path without '..'");
        return Undefined(env);
    }
    EmulatorService::Instance().QueueFileTransfer(local, remote);
    return Undefined(env);
}

napi_value ExitPressToTest(napi_env env, napi_callback_info)
{
    EmulatorService::Instance().QueueExitPressToTest();
    return Undefined(env);
}

napi_value ConfigureDebugger(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 1)
        return Rejected(env, "configureDebugger requires one configuration object");
    napi_value gdbPortValue, remotePortValue, startValue, warnValue, printValue;
    napi_get_named_property(env, args[0], "gdbPort", &gdbPortValue);
    napi_get_named_property(env, args[0], "remotePort", &remotePortValue);
    napi_get_named_property(env, args[0], "debugOnStart", &startValue);
    napi_get_named_property(env, args[0], "debugOnWarn", &warnValue);
    napi_get_named_property(env, args[0], "printOnWarn", &printValue);
    uint32_t gdbPort = 0, remotePort = 0;
    bool debugOnStartValue = false, debugOnWarnValue = false, printOnWarnValue = true;
    napi_get_value_uint32(env, gdbPortValue, &gdbPort);
    napi_get_value_uint32(env, remotePortValue, &remotePort);
    napi_get_value_bool(env, startValue, &debugOnStartValue);
    napi_get_value_bool(env, warnValue, &debugOnWarnValue);
    napi_get_value_bool(env, printValue, &printOnWarnValue);
    if (gdbPort > 65535 || remotePort > 65535)
        return Rejected(env, "Debugger ports must be 0 (disabled) or 1-65535");
    std::string error;
    if (!EmulatorService::Instance().ConfigureDebugger(gdbPort, remotePort, debugOnStartValue,
                                                        debugOnWarnValue, printOnWarnValue, error))
        return Rejected(env, error);
    return Resolved(env, Undefined(env));
}

napi_value EnterDebugger(napi_env env, napi_callback_info)
{
    EmulatorService::Instance().QueueEnterDebugger();
    return Undefined(env);
}

napi_value SendDebuggerCommand(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 1) {
        napi_throw_type_error(env, nullptr, "sendDebuggerCommand requires one command");
        return Undefined(env);
    }
    EmulatorService::Instance().QueueDebuggerCommand(GetString(env, args[0]));
    return Undefined(env);
}

napi_value GetDebugLog(napi_env env, napi_callback_info)
{
    return String(env, EmulatorService::Instance().DebugLog());
}

napi_value GetStatus(napi_env env, napi_callback_info)
{
    EmulatorStatus status = EmulatorService::Instance().Status();
    napi_value object;
    napi_create_object(env, &object);
    Set(env, object, "state", String(env, status.state));
    Set(env, object, "error", String(env, status.error));
    Set(env, object, "speed", Number(env, status.speed));
    Set(env, object, "fps", Number(env, status.fps));
    Set(env, object, "jitRequested", Boolean(env, status.jitRequested));
    Set(env, object, "jitProbePassed", Boolean(env, status.jitProbePassed));
    Set(env, object, "jitInitialized", Boolean(env, status.jitInitialized));
    Set(env, object, "translatedBlocks", Number(env, status.translatedBlocks));
    Set(env, object, "jitExecutionEntries", Number(env, status.jitExecutionEntries));
    Set(env, object, "product", Number(env, status.product));
    Set(env, object, "model", String(env, status.model));
    Set(env, object, "usbLinkConnected", Boolean(env, status.usbLinkConnected));
    Set(env, object, "transferProgress", Number(env, status.transferProgress));
    Set(env, object, "debuggerActive", Boolean(env, status.debuggerActive));
    Set(env, object, "debuggerWaitingForInput", Boolean(env, status.debuggerWaitingForInput));
    return object;
}

void CallStatusCallback(napi_env env, napi_value callback, void *, void *)
{
    if (!env || !callback)
        return;
    napi_value global;
    napi_get_global(env, &global);
    napi_value argument = GetStatus(env, nullptr);
    napi_value ignored;
    napi_call_function(env, global, callback, 1, &argument, &ignored);
}

void NotifyStatus()
{
    if (g_statusFunction)
        napi_call_threadsafe_function(g_statusFunction, nullptr, napi_tsfn_nonblocking);
}

napi_value SubscribeStatus(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    napi_valuetype type = napi_undefined;
    if (argc != 1 || napi_typeof(env, args[0], &type) != napi_ok || type != napi_function) {
        napi_throw_type_error(env, nullptr, "subscribeStatus requires a callback");
        return Undefined(env);
    }
    if (g_statusFunction) {
        napi_release_threadsafe_function(g_statusFunction, napi_tsfn_abort);
        g_statusFunction = nullptr;
    }
    napi_value resourceName = String(env, "FirebirdStatus");
    if (napi_create_threadsafe_function(env, args[0], nullptr, resourceName, 0, 1,
                                        nullptr, nullptr, nullptr, CallStatusCallback,
                                        &g_statusFunction) != napi_ok) {
        napi_throw_error(env, nullptr, "Could not create Firebird status channel");
        return Undefined(env);
    }
    EmulatorService::Instance().SetStatusNotifier(NotifyStatus);
    NotifyStatus();
    return Undefined(env);
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor functions[] = {
        {"probeJit", nullptr, ProbeJit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"validateFiles", nullptr, ValidateFiles, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"configure", nullptr, Configure, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pause", nullptr, Pause, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"resume", nullptr, Resume, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"restartCold", nullptr, RestartCold, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"saveSnapshot", nullptr, SaveSnapshot, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadSnapshot", nullptr, LoadSnapshot, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"inspectSnapshot", nullptr, InspectSnapshotFile, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setKeyState", nullptr, SetKeyState, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setTouchpadState", nullptr, SetTouchpadState, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"releaseAllInputs", nullptr, ReleaseAllInputs, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSpeedLimit", nullptr, SetSpeedLimit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sendFile", nullptr, SendFile, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"exitPressToTest", nullptr, ExitPressToTest, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"configureDebugger", nullptr, ConfigureDebugger, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"enterDebugger", nullptr, EnterDebugger, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sendDebuggerCommand", nullptr, SendDebuggerCommand, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getDebugLog", nullptr, GetDebugLog, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getStatus", nullptr, GetStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"subscribeStatus", nullptr, SubscribeStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(functions) / sizeof(functions[0]), functions);
    NativeRenderer::Instance().RegisterXComponent(env, exports);
    return exports;
}
}

static napi_module g_module {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "firebird_harmony",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterFirebirdHarmonyModule()
{
    napi_module_register(&g_module);
}
