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
// 함수 포인터 타입 — WebView2Loader.dll의 export 함수 시그니처와 일치해야 한다.
// ---------------------------------------------------------------------------

using FnCreateEnv = decltype(&CreateCoreWebView2EnvironmentWithOptions);
using FnGetVersion = decltype(&GetAvailableCoreWebView2BrowserVersionString);

// ---------------------------------------------------------------------------
// 모듈 전역 상태
//
// InitOnceExecuteOnce로 보호되므로 최초 호출 시에만 초기화가 실행된다.
// 이후 모든 호출은 캐시된 함수 포인터를 즉시 사용한다.
// ---------------------------------------------------------------------------

static INIT_ONCE   g_initOnce       = INIT_ONCE_STATIC_INIT;
static HMODULE     g_hModule        = nullptr;   // 로드된 DLL 핸들
static FnCreateEnv g_pfnCreateEnv   = nullptr;   // CreateEnvironment 함수 포인터
static FnGetVersion g_pfnGetVersion = nullptr;   // GetVersion 함수 포인터
static HRESULT     g_loadHR         = S_OK;      // 로드 결과 캐시 (실패 시 재시도 없음)
static wchar_t     g_tmpFile[MAX_PATH] = {};     // 리소스에서 추출한 임시 DLL 경로

// LoadLibraryW 전에 prepend 할 디렉터리 (SetDir로 설정, 첫 초기화 전에만 유효).
static wchar_t     g_dir[MAX_PATH]  = {};

// ---------------------------------------------------------------------------
// 리소스 로드 (standalone 모드)
//
// exe의 RT_RCDATA 리소스(KWV2_LOADER_DLL)에서 WebView2Loader.dll 바이트를
// 읽어 %TEMP% 임시 파일로 쓴 뒤 LoadLibraryExW로 로드한다.
// RFC-010 §2.2 Phase 3: LoadLibraryExW hardening — DLL 검색을 full path로 제한.
// 리소스가 없으면 false를 반환하고, 호출자는 일반 LoadLibrary 경로로 fallback한다.
// ---------------------------------------------------------------------------

/// DLL 핸들에서 두 개의 export 함수 포인터를 바인딩한다.
static bool BindExports(HMODULE hMod) {
    g_pfnCreateEnv = reinterpret_cast<FnCreateEnv>(
        GetProcAddress(hMod, "CreateCoreWebView2EnvironmentWithOptions"));
    g_pfnGetVersion = reinterpret_cast<FnGetVersion>(
        GetProcAddress(hMod, "GetAvailableCoreWebView2BrowserVersionString"));

    if (!g_pfnCreateEnv || !g_pfnGetVersion) {
        g_pfnCreateEnv = nullptr;
        g_pfnGetVersion = nullptr;
        return false;
    }
    g_hModule = hMod;
    return true;
}

/// exe에 내장된 RT_RCDATA 리소스에서 WebView2Loader.dll을 추출하여 로드한다.
/// standalone 배포(WebView2Loader.dll이 exe 옆에 없는 경우)를 지원한다.
static bool TryLoadFromResource() {
    HRSRC hRes = FindResourceW(nullptr, L"KWV2_LOADER_DLL", RT_RCDATA);
    if (!hRes) return false;

    HGLOBAL hGlob = LoadResource(nullptr, hRes);
    if (!hGlob) return false;

    void *data = LockResource(hGlob);
    DWORD size = SizeofResource(nullptr, hRes);
    if (!data || size == 0) return false;

    // 임시 파일 경로 생성
    wchar_t tmpDir[MAX_PATH] = {};
    wchar_t tmpFile[MAX_PATH] = {};
    if (!GetTempPathW(MAX_PATH, tmpDir)) return false;
    if (!GetTempFileNameW(tmpDir, L"kwv", 0, tmpFile)) return false;

    // 리소스 데이터를 임시 파일에 쓰기
    HANDLE hFile = CreateFileW(
        tmpFile,
        GENERIC_WRITE,
        0,
        nullptr,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
    if (hFile == INVALID_HANDLE_VALUE) return false;

    DWORD written = 0;
    BOOL ok = WriteFile(hFile, data, size, &written, nullptr);
    CloseHandle(hFile);
    if (!ok || written != size) {
        DeleteFileW(tmpFile);
        return false;
    }

    // RFC-010 Phase 3 Hardening: LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR를 사용하여
    // 지정된 full path에서만 DLL을 로드하고 시스템 경로에서는 로드하지 않는다.
    HMODULE hMod = LoadLibraryExW(tmpFile, nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR);
    if (!hMod) {
        DeleteFileW(tmpFile);
        return false;
    }

    if (!BindExports(hMod)) {
        FreeLibrary(hMod);
        DeleteFileW(tmpFile);
        return false;
    }

    // 프로세스 종료 시 임시 파일 정리를 위해 경로 저장
    wcsncpy_s(g_tmpFile, MAX_PATH, tmpFile, _TRUNCATE);
    return true;
}

// ---------------------------------------------------------------------------
// InitOnce 콜백 — 최초 1회만 실행된다.
// ---------------------------------------------------------------------------

static BOOL CALLBACK LoadOnce(PINIT_ONCE, PVOID, PVOID *) {
    // standalone 모드: exe 리소스에서 우선 로드 시도
    if (TryLoadFromResource()) {
        g_loadHR = S_OK;
        return TRUE;
    }

    // 디렉터리가 설정되어 있으면 SetDllDirectoryW로 검색 경로에 prepend
    // (기존 검색 순서는 유지).
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

    if (!BindExports(hMod)) {
        FreeLibrary(hMod);
        g_loadHR = HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
        return TRUE;
    }
    g_loadHR = S_OK;
    return TRUE;
}

// ---------------------------------------------------------------------------
// 공개 API
// ---------------------------------------------------------------------------

/// DLL 검색 디렉터리를 설정한다. 첫 번째 Ensure() 이전에만 유효하다.
void KSWV2_Loader_SetDir(const wchar_t *dir) {
    if (!dir) return;
    // InitOnce가 이미 완료된 경우 g_dir 변경은 효과가 없다 — 문서화된 제약.
    wcsncpy_s(g_dir, MAX_PATH, dir, _TRUNCATE);
}

/// InitOnce를 통해 LoadOnce를 1회 실행하고, 캐시된 로드 결과를 반환한다.
static HRESULT Ensure() {
    InitOnceExecuteOnce(&g_initOnce, LoadOnce, nullptr, nullptr);
    return g_loadHR;
}

/// CreateCoreWebView2EnvironmentWithOptions를 동적 디스패치한다.
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

/// GetAvailableCoreWebView2BrowserVersionString을 동적 디스패치한다.
HRESULT KSWV2_Loader_GetAvailableBrowserVersionString(
    PCWSTR browserExecutableFolder,
    LPWSTR *versionInfo)
{
    HRESULT hr = Ensure();
    if (FAILED(hr)) return hr;
    return g_pfnGetVersion(browserExecutableFolder, versionInfo);
}
