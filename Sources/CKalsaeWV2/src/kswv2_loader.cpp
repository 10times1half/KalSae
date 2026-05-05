//
//  kswv2_loader.cpp
//  CKalsaeWV2
//
//  WebView2Loader.dll을 LoadLibraryW로 런타임에 로드하고,
//  CreateCoreWebView2EnvironmentWithOptions와
//  GetAvailableCoreWebView2BrowserVersionString
//  두 함수 포인터를 스레드 안전하게 한 번만 초기화한다.
//
//  고정 런타임 모드(fixed-runtime)를 지원하기 위해 KSWV2_Loader_SetDir()로
//  DLL 검색 디렉터리를 LoadLibraryW 이전에 prepend할 수 있다.
//

#include "kswv2_loader.h"
#include <synchapi.h>    // InitOnceExecuteOnce

// ---------------------------------------------------------------------------
// 함수 포인터 타입
// ---------------------------------------------------------------------------

using FnCreateEnv = decltype(&CreateCoreWebView2EnvironmentWithOptions);
using FnGetVersion = decltype(&GetAvailableCoreWebView2BrowserVersionString);

// ---------------------------------------------------------------------------
// 모듈 전역 상태
// ---------------------------------------------------------------------------

static INIT_ONCE   g_initOnce       = INIT_ONCE_STATIC_INIT;
static HMODULE     g_hModule        = nullptr;
static FnCreateEnv g_pfnCreateEnv   = nullptr;
static FnGetVersion g_pfnGetVersion = nullptr;
static HRESULT     g_loadHR         = S_OK;  // 로드 결과 캐시

// LoadLibraryW 전에 prepend 할 디렉터리 (SetDir로 설정, 첫 초기화 전에만 유효).
static wchar_t     g_dir[MAX_PATH]  = {};

// ---------------------------------------------------------------------------
// InitOnce 콜백
// ---------------------------------------------------------------------------

static BOOL CALLBACK LoadOnce(PINIT_ONCE, PVOID, PVOID *) {
    // 디렉터리가 설정되어 있으면 prepend (기존 검색 순서는 유지).
    if (g_dir[0] != L'\0') {
        SetDllDirectoryW(g_dir);
    }

    HMODULE hMod = LoadLibraryW(L"WebView2Loader.dll");

    // SetDllDirectoryW를 원복해 다른 LoadLibraryW 호출에 영향을 주지 않는다.
    if (g_dir[0] != L'\0') {
        SetDllDirectoryW(nullptr);
    }

    if (!hMod) {
        g_loadHR = HRESULT_FROM_WIN32(GetLastError());
        return TRUE;  // InitOnce는 1회만 실행 — 실패도 "완료"로 처리
    }

    g_pfnCreateEnv = reinterpret_cast<FnCreateEnv>(
        GetProcAddress(hMod, "CreateCoreWebView2EnvironmentWithOptions"));
    g_pfnGetVersion = reinterpret_cast<FnGetVersion>(
        GetProcAddress(hMod, "GetAvailableCoreWebView2BrowserVersionString"));

    if (!g_pfnCreateEnv || !g_pfnGetVersion) {
        FreeLibrary(hMod);
        g_loadHR = HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
        return TRUE;
    }

    g_hModule = hMod;
    return TRUE;
}

// ---------------------------------------------------------------------------
// 공개 API
// ---------------------------------------------------------------------------

void KSWV2_Loader_SetDir(const wchar_t *dir) {
    if (!dir) return;
    // SetDir는 첫 번째 Ensure 이전에만 유효하다.
    // InitOnce가 이미 완료된 경우 g_dir 변경은 효과가 없다 — 문서화된 제약.
    wcsncpy_s(g_dir, MAX_PATH, dir, _TRUNCATE);
}

static HRESULT Ensure() {
    InitOnceExecuteOnce(&g_initOnce, LoadOnce, nullptr, nullptr);
    return g_loadHR;
}

HRESULT KSWV2_Loader_CreateEnvironmentWithOptions(
    PCWSTR browserExecutableFolder,
    PCWSTR userDataFolder,
    ICoreWebView2EnvironmentOptions *environmentOptions,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *environmentCreatedHandler)
{
    HRESULT hr = Ensure();
    if (FAILED(hr)) return hr;
    return g_pfnCreateEnv(
        browserExecutableFolder,
        userDataFolder,
        environmentOptions,
        environmentCreatedHandler);
}

HRESULT KSWV2_Loader_GetAvailableBrowserVersionString(
    PCWSTR browserExecutableFolder,
    LPWSTR *versionInfo)
{
    HRESULT hr = Ensure();
    if (FAILED(hr)) return hr;
    return g_pfnGetVersion(browserExecutableFolder, versionInfo);
}
