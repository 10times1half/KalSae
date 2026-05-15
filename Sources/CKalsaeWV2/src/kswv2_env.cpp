//
//  kswv2_env.cpp
//  CKalsaeWV2
//
//  Environment + Controller 생명주기:
//  CreateCoreWebView2Environment, CreateCoreWebView2Controller,
//  controller의 위치/크기/가시성/닫기, 그리고 버전 문자열 조회.
//

#include <wrl.h>
#include <objbase.h>           // CoTaskMemFree
#include <windows.h>
#include <stdio.h>
#include "kswv2_internal.h"
#include "../Vendor/WebView2/build/native/include/WebView2EnvironmentOptions.h"

using namespace Microsoft::WRL;

// SEH(Structured Exception Handling)로 Swift 환경 완료 콜백을 안전하게 호출한다.
// WebView2는 WRL 핸들러를 UI 스레드에서 호출하는데, 만약 Swift 측에서
// 구조적 예외(fatalError, executor-check trap 등)를 발생시키면 그 예외가
// WRL 콜백 경계를 넘어 전파되어 Windows가 STATUS_FATAL_USER_CALLBACK_EXCEPTION
// (0xC000041D)으로 프로세스를 종료시킨다. SEH로 잡아서 로그만 남기고
// 실패를 반환함으로써 크래시를 방지한다.
static int32_t ks_invoke_env_completed_safe(
    KSWV2EnvCompletedCB cb, void *user, int32_t hr, KSWV2Env env)
{
    __try {
        cb(user, hr, env);
        return 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        DWORD code = GetExceptionCode();
        char buf[160];
        int n = _snprintf_s(buf, sizeof(buf), _TRUNCATE,
            "[diag-cpp] SEH escaped Swift env completion callback: code=0x%08X\n",
            (unsigned)code);
        if (n > 0) {
            DWORD w = 0;
            WriteFile(GetStdHandle(STD_ERROR_HANDLE), buf, (DWORD)n, &w, NULL);
        }
        return (int32_t)code;
    }
}

// MARK: - 환경 (Environment)

extern "C" void KSWV2_SetLoaderSearchDirectory(const wchar_t *dir) {
    KSWV2_Loader_SetDir(dir);
}

/// 기본 환경 생성 — CreateEnvironmentEx에 nullptr 옵션으로 위임한다.
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

/// 확장 환경 생성 — KSWV2EnvOptions의 각 필드를 해당 COM 인터페이스에 설정한다.
/// Options2/3/5는 QueryInterface로 업캐스트하여 설정하므로, 런타임이 해당
/// 인터페이스를 지원하지 않으면 자동으로 무시된다.
extern "C" int32_t KSWV2_CreateEnvironmentEx(
    const wchar_t *browser_executable_folder,
    const wchar_t *user_data_folder,
    const KSWV2EnvOptions *opts,
    void *user,
    KSWV2EnvCompletedCB completed)
{
    if (!completed) return E_POINTER;

    // WRL Callback으로 환경 생성 완료 핸들러 생성
    auto handler = Callback<
        ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
        [user, completed](HRESULT hr, ICoreWebView2Environment *env) -> HRESULT {
            if (SUCCEEDED(hr) && env) env->AddRef();
            ks_invoke_env_completed_safe(
                completed, user, static_cast<int32_t>(hr),
                reinterpret_cast<KSWV2Env>(env));
            return S_OK;
        });

    ComPtr<ICoreWebView2EnvironmentOptions> options;
    if (opts) {
        // 기본 옵션 객체 생성
        auto base = Make<CoreWebView2EnvironmentOptions>();
        if (!base) return E_OUTOFMEMORY;

        // 기본 옵션 (ICoreWebView2EnvironmentOptions)
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

        // Options2: ExclusiveUserDataFolderAccess — 사용자 데이터 폴더를
        // 다른 프로세스와 공유하지 않도록 설정한다.
        ComPtr<ICoreWebView2EnvironmentOptions2> opts2;
        if (opts->exclusive_user_data_folder_access >= 0
            && SUCCEEDED(base.As(&opts2)) && opts2)
        {
            opts2->put_ExclusiveUserDataFolderAccess(
                opts->exclusive_user_data_folder_access ? TRUE : FALSE);
        }
        // Options3: IsCustomCrashReportingEnabled — 사용자 정의 크래시
        // 리포팅을 활성화/비활성화한다.
        ComPtr<ICoreWebView2EnvironmentOptions3> opts3;
        if (opts->custom_crash_reporting_enabled >= 0
            && SUCCEEDED(base.As(&opts3)) && opts3)
        {
            opts3->put_IsCustomCrashReportingEnabled(
                opts->custom_crash_reporting_enabled ? TRUE : FALSE);
        }
        // Options5: EnableTrackingPrevention — 추적 방지 기능을
        // 활성화/비활성화한다.
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

/// 환경 객체의 참조 카운트를 해제한다.
extern "C" void KSWV2_Env_Release(KSWV2Env env) {
    if (env) KSWV2_AsEnv(env)->Release();
}

/// 사용 가능한 WebView2 브라우저 버전 문자열을 조회한다.
/// 반환된 문자열은 호출자가 CoTaskMemFree로 해제해야 한다.
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

// MARK: - 컨트롤러 (Controller)

/// 주어진 HWND에 WebView2 컨트롤러를 생성한다.
/// 완료 시 completed 콜백이 호출된다.
extern "C" int32_t KSWV2_CreateController(
    KSWV2Env env,
    void *hwnd,
    void *user,
    KSWV2ControllerCompletedCB completed)
{
    if (!env || !hwnd || !completed) return E_POINTER;

    // WRL Callback으로 컨트롤러 생성 완료 핸들러 생성
    auto handler = Callback<
        ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
        [user, completed](HRESULT hr, ICoreWebView2Controller *ctrl) -> HRESULT {
            if (SUCCEEDED(hr) && ctrl) ctrl->AddRef();
            // SEH 가드: Swift 콜백에서 발생하는 예외를 잡아 크래시 방지
            __try {
                completed(user, static_cast<int32_t>(hr),
                          reinterpret_cast<KSWV2Controller>(ctrl));
            } __except (EXCEPTION_EXECUTE_HANDLER) {
                DWORD code = GetExceptionCode();
                char buf[160];
                int n = _snprintf_s(buf, sizeof(buf), _TRUNCATE,
                    "[diag-cpp] SEH escaped Swift controller completion callback: code=0x%08X\n",
                    (unsigned)code);
                if (n > 0) {
                    DWORD w = 0;
                    WriteFile(GetStdHandle(STD_ERROR_HANDLE), buf, (DWORD)n, &w, NULL);
                }
            }
            return S_OK;
        });

    return static_cast<int32_t>(
        KSWV2_AsEnv(env)->CreateCoreWebView2Controller(
            reinterpret_cast<HWND>(hwnd), handler.Get()));
}

/// 컨트롤러의 참조 카운트를 해제한다.
extern "C" void KSWV2_Controller_Release(KSWV2Controller controller) {
    if (controller) KSWV2_AsController(controller)->Release();
}

/// 컨트롤러로부터 WebView 인터페이스를 얻는다.
/// 반환된 포인터는 빌린 참조이므로 AddRef하지 않는다.
extern "C" KSWV2WebView KSWV2_Controller_GetWebView(KSWV2Controller controller) {
    if (!controller) return nullptr;
    ICoreWebView2 *wv = nullptr;
    if (FAILED(KSWV2_AsController(controller)->get_CoreWebView2(&wv))) return nullptr;
    return reinterpret_cast<KSWV2WebView>(wv);  // 빌린 포인터, AddRef 안 함
}

/// 컨트롤러의 위치와 크기를 설정한다.
extern "C" int32_t KSWV2_Controller_SetBounds(
    KSWV2Controller controller, int32_t x, int32_t y, int32_t w, int32_t h)
{
    if (!controller) return E_POINTER;
    RECT r = { x, y, x + w, y + h };
    return static_cast<int32_t>(KSWV2_AsController(controller)->put_Bounds(r));
}

/// 컨트롤러의 가시성을 설정한다.
extern "C" int32_t KSWV2_Controller_SetVisible(
    KSWV2Controller controller, int32_t visible)
{
    if (!controller) return E_POINTER;
    return static_cast<int32_t>(
        KSWV2_AsController(controller)->put_IsVisible(visible ? TRUE : FALSE));
}

/// 컨트롤러를 닫고 관련 리소스를 정리한다.
extern "C" int32_t KSWV2_Controller_Close(KSWV2Controller controller) {
    if (!controller) return E_POINTER;
    return static_cast<int32_t>(KSWV2_AsController(controller)->Close());
}

/// 컨트롤러의 AllowExternalDrop 플래그를 설정한다 (ICoreWebView2Controller4).
/// Runtime 1.0.992+ 필요. 이전 런타임에서는 E_NOINTERFACE 반환.
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
