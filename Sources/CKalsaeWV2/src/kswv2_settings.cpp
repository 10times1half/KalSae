//
//  kswv2_settings.cpp
//  CKalsaeWV2
//
//  WebView2 Settings 토글 (Phase A4).
//  모든 함수는 트라이스테이트 정수를 받는다 (-1 = 미설정/no-op, 0 = OFF, 1 = ON).
//  인터페이스가 미지원이면 E_NOINTERFACE를 그대로 반환한다.
//

#include <wrl.h>
#include "kswv2_internal.h"

using namespace Microsoft::WRL;

/// ICoreWebView2Settings를 얻는 헬퍼. 호출자는 Release()해야 한다.
static ICoreWebView2Settings *GetSettings(KSWV2WebView webview) {
    if (!webview) return nullptr;
    ICoreWebView2Settings *s = nullptr;
    if (FAILED(KSWV2_AsWebView(webview)->get_Settings(&s))) return nullptr;
    return s;
}

/// JavaScript 실행 활성화/비활성화.
extern "C" int32_t KSWV2_SetScriptEnabled(KSWV2WebView webview, int32_t enabled) {
    if (enabled < 0) return 0;
    ICoreWebView2Settings *s = GetSettings(webview);
    if (!s) return E_POINTER;
    HRESULT hr = s->put_IsScriptEnabled(enabled ? TRUE : FALSE);
    s->Release();
    return static_cast<int32_t>(hr);
}

/// 상태 표시줄 표시 활성화/비활성화.
extern "C" int32_t KSWV2_SetStatusBarEnabled(KSWV2WebView webview, int32_t enabled) {
    if (enabled < 0) return 0;
    ICoreWebView2Settings *s = GetSettings(webview);
    if (!s) return E_POINTER;
    HRESULT hr = s->put_IsStatusBarEnabled(enabled ? TRUE : FALSE);
    s->Release();
    return static_cast<int32_t>(hr);
}

/// Ctrl+/- 줌 제어 활성화/비활성화.
extern "C" int32_t KSWV2_SetZoomControlEnabled(KSWV2WebView webview, int32_t enabled) {
    if (enabled < 0) return 0;
    ICoreWebView2Settings *s = GetSettings(webview);
    if (!s) return E_POINTER;
    HRESULT hr = s->put_IsZoomControlEnabled(enabled ? TRUE : FALSE);
    s->Release();
    return static_cast<int32_t>(hr);
}

/// WebView2 기본 오류 페이지 활성화/비활성화.
extern "C" int32_t KSWV2_SetBuiltInErrorPageEnabled(
    KSWV2WebView webview, int32_t enabled)
{
    if (enabled < 0) return 0;
    ICoreWebView2Settings *s = GetSettings(webview);
    if (!s) return E_POINTER;
    HRESULT hr = s->put_IsBuiltInErrorPageEnabled(enabled ? TRUE : FALSE);
    s->Release();
    return static_cast<int32_t>(hr);
}

/// 자동 완성(일반 + 비밀번호 저장) 활성화/비활성화 (Settings4).
extern "C" int32_t KSWV2_SetAutofillEnabled(KSWV2WebView webview, int32_t enabled) {
    if (enabled < 0) return 0;
    ICoreWebView2Settings *s = GetSettings(webview);
    if (!s) return E_POINTER;
    // Settings4로 QI
    ComPtr<ICoreWebView2Settings4> s4;
    HRESULT hr = s->QueryInterface(IID_PPV_ARGS(&s4));
    s->Release();
    if (FAILED(hr) || !s4) return static_cast<int32_t>(hr);
    BOOL val = enabled ? TRUE : FALSE;
    hr = s4->put_IsGeneralAutofillEnabled(val);
    if (SUCCEEDED(hr)) hr = s4->put_IsPasswordAutosaveEnabled(val);
    return static_cast<int32_t>(hr);
}

/// 뒤로/앞으로 스와이프 내비게이션 활성화/비활성화 (Settings6).
extern "C" int32_t KSWV2_SetSwipeNavigationEnabled(
    KSWV2WebView webview, int32_t enabled)
{
    if (enabled < 0) return 0;
    ICoreWebView2Settings *s = GetSettings(webview);
    if (!s) return E_POINTER;
    ComPtr<ICoreWebView2Settings6> s6;
    HRESULT hr = s->QueryInterface(IID_PPV_ARGS(&s6));
    s->Release();
    if (FAILED(hr) || !s6) return static_cast<int32_t>(hr);
    hr = s6->put_IsSwipeNavigationEnabled(enabled ? TRUE : FALSE);
    return static_cast<int32_t>(hr);
}

/// SmartScreen 평판 확인 활성화/비활성화 (Settings9).
extern "C" int32_t KSWV2_SetReputationCheckingRequired(
    KSWV2WebView webview, int32_t enabled)
{
    if (enabled < 0) return 0;
    ICoreWebView2Settings *s = GetSettings(webview);
    if (!s) return E_POINTER;
    ComPtr<ICoreWebView2Settings9> s9;
    HRESULT hr = s->QueryInterface(IID_PPV_ARGS(&s9));
    s->Release();
    if (FAILED(hr) || !s9) return static_cast<int32_t>(hr);
    hr = s9->put_IsReputationCheckingRequired(enabled ? TRUE : FALSE);
    return static_cast<int32_t>(hr);
}

/// 핀치 줌 활성화/비활성화 (Settings5).
extern "C" int32_t KSWV2_SetPinchZoomEnabled(KSWV2WebView webview, int32_t enabled) {
    if (enabled < 0) return 0;
    ICoreWebView2Settings *s = GetSettings(webview);
    if (!s) return E_POINTER;
    ComPtr<ICoreWebView2Settings5> s5;
    HRESULT hr = s->QueryInterface(IID_PPV_ARGS(&s5));
    s->Release();
    if (FAILED(hr) || !s5) return static_cast<int32_t>(hr);
    hr = s5->put_IsPinchZoomEnabled(enabled ? TRUE : FALSE);
    return static_cast<int32_t>(hr);
}
