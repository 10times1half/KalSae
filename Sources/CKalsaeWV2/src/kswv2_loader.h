//
//  kswv2_loader.h
//  CKalsaeWV2
//
//  동적 WebView2 로더.
//
//  WebView2LoaderStatic.lib 정적 링크 대신 LoadLibraryW("WebView2Loader.dll")로
//  런타임에 로더 DLL을 찾아 두 개의 export 함수 포인터를 캐시한다.
//  그 외의 모든 WebView2 API는 COM vtable 호출이므로 이 헤더와 무관하다.
//

#ifndef KSWV2_LOADER_H
#define KSWV2_LOADER_H

#include <windows.h>
#include <WebView2.h>   // ICoreWebView2* vtable 선언용 헤더는 그대로 사용

// ---------------------------------------------------------------------------
// 초기화 (선택적). 첫 번째 LoadLibraryW 이전에 DLL 검색 경로를 prepend한다.
// fixed-runtime 모드에서 "webview2-runtime/" 을 우선 검색하도록 BuildCommand가
// 패키지 디렉터리 내 경로를 전달한다.
// dir == nullptr 이면 no-op.
// ---------------------------------------------------------------------------
void KSWV2_Loader_SetDir(const wchar_t *dir);

// ---------------------------------------------------------------------------
// 동적 디스패치 — WebView2LoaderStatic.lib 의 두 export를 대체한다.
// ---------------------------------------------------------------------------

/// CreateCoreWebView2EnvironmentWithOptions 동적 디스패치.
/// WebView2Loader.dll 로드 실패 시 HRESULT_FROM_WIN32(ERROR_MOD_NOT_FOUND) 반환.
HRESULT KSWV2_Loader_CreateEnvironmentWithOptions(
    PCWSTR browserExecutableFolder,
    PCWSTR userDataFolder,
    ICoreWebView2EnvironmentOptions *environmentOptions,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *environmentCreatedHandler);

/// GetAvailableCoreWebView2BrowserVersionString 동적 디스패치.
HRESULT KSWV2_Loader_GetAvailableBrowserVersionString(
    PCWSTR browserExecutableFolder,
    LPWSTR *versionInfo);

#endif // KSWV2_LOADER_H
