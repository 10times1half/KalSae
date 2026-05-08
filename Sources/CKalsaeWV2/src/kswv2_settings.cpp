//
//  kswv2_settings.cpp
//  CKalsaeWV2
//
//  Phase A4 — `ICoreWebView2Settings*` 토글 묶음.
//
//  각 함수는 트라이스테이트 정수를 받는다:
//   -1 = 미설정 (no-op, S_OK 반환)
//    0 = OFF
//    1 = ON
//
//  Settings4/5/6/9 가 미지원이면 `E_NOINTERFACE` 를 그대로 반환한다.
//  호출자는 기능 보고서(KSWebViewCapabilityReport)에 기록한다.
//

#include "kswv2_internal.h"

namespace {

// 트라이스테이트 헬퍼: -1 이면 즉시 통과.
inline bool TriskipUnset(int32_t value) { return value < 0; }

// `get_Settings` 후 `Setter(BOOL)` 람다를 호출하는 공통 패턴.
template <typename SetterFn>
int32_t WithSettings(KSWV2WebView webview, int32_t value, SetterFn setter) {
    if (TriskipUnset(value)) return S_OK;
    if (!webview) return E_POINTER;
    ICoreWebView2Settings *settings = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->get_Settings(&settings);
    if (FAILED(hr) || !settings) return static_cast<int32_t>(hr);
    hr = setter(settings, value ? TRUE : FALSE);
    settings->Release();
    return static_cast<int32_t>(hr);
}

// 더 새 인터페이스로 QI 후 setter 호출.
template <typename Iface, typename SetterFn>
int32_t WithSettingsAs(KSWV2WebView webview, int32_t value, REFIID iid, SetterFn setter) {
    if (TriskipUnset(value)) return S_OK;
    if (!webview) return E_POINTER;
    ICoreWebView2Settings *settings = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->get_Settings(&settings);
    if (FAILED(hr) || !settings) return static_cast<int32_t>(hr);
    Iface *upgraded = nullptr;
    hr = settings->QueryInterface(iid, reinterpret_cast<void **>(&upgraded));
    settings->Release();
    if (FAILED(hr) || !upgraded) {
        return static_cast<int32_t>(hr ? hr : E_NOINTERFACE);
    }
    hr = setter(upgraded, value ? TRUE : FALSE);
    upgraded->Release();
    return static_cast<int32_t>(hr);
}

} // namespace

extern "C" int32_t KSWV2_SetScriptEnabled(KSWV2WebView webview, int32_t enabled) {
    return WithSettings(webview, enabled, [](ICoreWebView2Settings *s, BOOL v) {
        return s->put_IsScriptEnabled(v);
    });
}

extern "C" int32_t KSWV2_SetStatusBarEnabled(KSWV2WebView webview, int32_t enabled) {
    return WithSettings(webview, enabled, [](ICoreWebView2Settings *s, BOOL v) {
        return s->put_IsStatusBarEnabled(v);
    });
}

extern "C" int32_t KSWV2_SetZoomControlEnabled(KSWV2WebView webview, int32_t enabled) {
    return WithSettings(webview, enabled, [](ICoreWebView2Settings *s, BOOL v) {
        return s->put_IsZoomControlEnabled(v);
    });
}

extern "C" int32_t KSWV2_SetBuiltInErrorPageEnabled(KSWV2WebView webview, int32_t enabled) {
    return WithSettings(webview, enabled, [](ICoreWebView2Settings *s, BOOL v) {
        return s->put_IsBuiltInErrorPageEnabled(v);
    });
}

extern "C" int32_t KSWV2_SetAutofillEnabled(KSWV2WebView webview, int32_t enabled) {
    // Settings4: IsGeneralAutofillEnabled + IsPasswordAutosaveEnabled 일괄.
    if (TriskipUnset(enabled)) return S_OK;
    if (!webview) return E_POINTER;
    ICoreWebView2Settings *settings = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->get_Settings(&settings);
    if (FAILED(hr) || !settings) return static_cast<int32_t>(hr);
    ICoreWebView2Settings4 *s4 = nullptr;
    hr = settings->QueryInterface(IID_PPV_ARGS(&s4));
    settings->Release();
    if (FAILED(hr) || !s4) {
        return static_cast<int32_t>(hr ? hr : E_NOINTERFACE);
    }
    BOOL v = enabled ? TRUE : FALSE;
    HRESULT hr1 = s4->put_IsGeneralAutofillEnabled(v);
    HRESULT hr2 = s4->put_IsPasswordAutosaveEnabled(v);
    s4->Release();
    return static_cast<int32_t>(FAILED(hr1) ? hr1 : hr2);
}

extern "C" int32_t KSWV2_SetSwipeNavigationEnabled(KSWV2WebView webview, int32_t enabled) {
    return WithSettingsAs<ICoreWebView2Settings6>(
        webview, enabled,
        IID_ICoreWebView2Settings6,
        [](ICoreWebView2Settings6 *s, BOOL v) {
            return s->put_IsSwipeNavigationEnabled(v);
        });
}

extern "C" int32_t KSWV2_SetReputationCheckingRequired(KSWV2WebView webview, int32_t enabled) {
    return WithSettingsAs<ICoreWebView2Settings9>(
        webview, enabled,
        IID_ICoreWebView2Settings9,
        [](ICoreWebView2Settings9 *s, BOOL v) {
            return s->put_IsReputationCheckingRequired(v);
        });
}
