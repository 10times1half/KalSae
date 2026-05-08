//
//  kswv2_env.cpp
//  CKalsaeWV2
//
//  Environment + Controller lifecycle: `CreateCoreWebView2Environment`,
//  `CreateCoreWebView2Controller`, controller geometry/visibility/close,
//  and the version-string query.
//

#include <wrl.h>
#include <objbase.h>           // CoTaskMemFree
#include "kswv2_internal.h"
#include "../Vendor/WebView2/build/native/include/WebView2EnvironmentOptions.h"

using namespace Microsoft::WRL;

// MARK: - Environment

extern "C" void KSWV2_SetLoaderSearchDirectory(const wchar_t *dir) {
    KSWV2_Loader_SetDir(dir);
}

extern "C" int32_t KSWV2_CreateEnvironment(
    const wchar_t *browser_executable_folder,
    const wchar_t *user_data_folder,
    void *user,
    KSWV2EnvCompletedCB completed)
{
    return KSWV2_CreateEnvironmentEx(
        browser_executable_folder, user_data_folder,
        nullptr, user, completed);
}

extern "C" int32_t KSWV2_CreateEnvironmentEx(
    const wchar_t *browser_executable_folder,
    const wchar_t *user_data_folder,
    const KSWV2EnvOptions *opts,
    void *user,
    KSWV2EnvCompletedCB completed)
{
    if (!completed) return E_POINTER;

    auto handler = Callback<
        ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
        [user, completed](HRESULT hr, ICoreWebView2Environment *env) -> HRESULT {
            if (SUCCEEDED(hr) && env) env->AddRef();
            completed(user, static_cast<int32_t>(hr),
                      reinterpret_cast<KSWV2Env>(env));
            return S_OK;
        });

    ComPtr<ICoreWebView2EnvironmentOptions> options;
    if (opts) {
        auto base = Make<CoreWebView2EnvironmentOptions>();
        if (!base) return E_OUTOFMEMORY;

        if (opts->additional_browser_arguments)
            base->put_AdditionalBrowserArguments(
                opts->additional_browser_arguments);
        if (opts->language)
            base->put_Language(opts->language);
        if (opts->target_compatible_browser_version)
            base->put_TargetCompatibleBrowserVersion(
                opts->target_compatible_browser_version);
        if (opts->allow_single_sign_on >= 0)
            base->put_AllowSingleSignOnUsingOSPrimaryAccount(
                opts->allow_single_sign_on ? TRUE : FALSE);

        // Options2: ExclusiveUserDataFolderAccess.
        ComPtr<ICoreWebView2EnvironmentOptions2> opts2;
        if (opts->exclusive_user_data_folder_access >= 0
            && SUCCEEDED(base.As(&opts2)) && opts2)
        {
            opts2->put_ExclusiveUserDataFolderAccess(
                opts->exclusive_user_data_folder_access ? TRUE : FALSE);
        }
        // Options3: IsCustomCrashReportingEnabled.
        ComPtr<ICoreWebView2EnvironmentOptions3> opts3;
        if (opts->custom_crash_reporting_enabled >= 0
            && SUCCEEDED(base.As(&opts3)) && opts3)
        {
            opts3->put_IsCustomCrashReportingEnabled(
                opts->custom_crash_reporting_enabled ? TRUE : FALSE);
        }
        // Options5: EnableTrackingPrevention.
        ComPtr<ICoreWebView2EnvironmentOptions5> opts5;
        if (opts->enable_tracking_prevention >= 0
            && SUCCEEDED(base.As(&opts5)) && opts5)
        {
            opts5->put_EnableTrackingPrevention(
                opts->enable_tracking_prevention ? TRUE : FALSE);
        }

        options = base;
    }

    return static_cast<int32_t>(
        KSWV2_Loader_CreateEnvironmentWithOptions(
            browser_executable_folder,
            user_data_folder,
            options.Get(),
            handler.Get()));
}

extern "C" void KSWV2_Env_Release(KSWV2Env env) {
    if (env) KSWV2_AsEnv(env)->Release();
}

extern "C" int32_t KSWV2_GetAvailableBrowserVersion(
    const wchar_t *browser_executable_folder,
    wchar_t **version_out)
{
    LPWSTR v = nullptr;
    HRESULT hr = KSWV2_Loader_GetAvailableBrowserVersionString(
        browser_executable_folder, &v);
    if (version_out) {
        *version_out = v;          // 호출자가 CoTaskMemFree로 해제
    } else if (v) {
        CoTaskMemFree(v);
    }
    return static_cast<int32_t>(hr);
}

// MARK: - Controller

extern "C" int32_t KSWV2_CreateController(
    KSWV2Env env,
    void *hwnd,
    void *user,
    KSWV2ControllerCompletedCB completed)
{
    if (!env || !hwnd || !completed) return E_POINTER;

    auto handler = Callback<
        ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
        [user, completed](HRESULT hr, ICoreWebView2Controller *ctrl) -> HRESULT {
            if (SUCCEEDED(hr) && ctrl) ctrl->AddRef();
            completed(user, static_cast<int32_t>(hr),
                      reinterpret_cast<KSWV2Controller>(ctrl));
            return S_OK;
        });

    return static_cast<int32_t>(
        KSWV2_AsEnv(env)->CreateCoreWebView2Controller(
            reinterpret_cast<HWND>(hwnd), handler.Get()));
}

extern "C" void KSWV2_Controller_Release(KSWV2Controller controller) {
    if (controller) KSWV2_AsController(controller)->Release();
}

extern "C" KSWV2WebView KSWV2_Controller_GetWebView(KSWV2Controller controller) {
    if (!controller) return nullptr;
    ICoreWebView2 *wv = nullptr;
    if (FAILED(KSWV2_AsController(controller)->get_CoreWebView2(&wv))) return nullptr;
    return reinterpret_cast<KSWV2WebView>(wv);  // 빌린 포인터, AddRef 안 함
}

extern "C" int32_t KSWV2_Controller_SetBounds(
    KSWV2Controller controller, int32_t x, int32_t y, int32_t w, int32_t h)
{
    if (!controller) return E_POINTER;
    RECT r = { x, y, x + w, y + h };
    return static_cast<int32_t>(KSWV2_AsController(controller)->put_Bounds(r));
}

extern "C" int32_t KSWV2_Controller_SetVisible(
    KSWV2Controller controller, int32_t visible)
{
    if (!controller) return E_POINTER;
    return static_cast<int32_t>(
        KSWV2_AsController(controller)->put_IsVisible(visible ? TRUE : FALSE));
}

extern "C" int32_t KSWV2_Controller_Close(KSWV2Controller controller) {
    if (!controller) return E_POINTER;
    return static_cast<int32_t>(KSWV2_AsController(controller)->Close());
}

extern "C" int32_t KSWV2_Controller_SetAllowExternalDrop(
    KSWV2Controller controller, int32_t allow)
{
    if (!controller) return E_POINTER;
    Microsoft::WRL::ComPtr<ICoreWebView2Controller4> c4;
    HRESULT hr = KSWV2_AsController(controller)->QueryInterface(IID_PPV_ARGS(&c4));
    if (FAILED(hr)) return static_cast<int32_t>(hr);
    return static_cast<int32_t>(
        c4->put_AllowExternalDrop(allow ? TRUE : FALSE));
}
