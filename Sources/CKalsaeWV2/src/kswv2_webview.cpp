//
//  kswv2_webview.cpp
//  CKalsaeWV2
//
//  WebView-level operations: navigation, message handlers, settings
//  toggles, virtual host mapping, document-created scripts.
//

#include <wrl.h>
#include <objbase.h>
#include "kswv2_internal.h"

using namespace Microsoft::WRL;

extern "C" int32_t KSWV2_Navigate(KSWV2WebView webview, const wchar_t *url) {
    if (!webview || !url) return E_POINTER;
    return static_cast<int32_t>(KSWV2_AsWebView(webview)->Navigate(url));
}

extern "C" int32_t KSWV2_AddMessageHandler(
    KSWV2WebView webview, void *user, KSWV2MessageCB cb)
{
    if (!webview || !cb) return E_POINTER;

    auto handler = Callback<ICoreWebView2WebMessageReceivedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2WebMessageReceivedEventArgs *args) -> HRESULT {
            // 구조화된 페이로드가 알차게 전달되도록 단순 문자열보다 JSON을 우선한다.
            LPWSTR json = nullptr;
            HRESULT hr = args->get_WebMessageAsJson(&json);
            if (SUCCEEDED(hr) && json) {
                cb(user, json);
                CoTaskMemFree(json);
            } else {
                // 문자열 형태로 폴백해 `postMessage("hi")`도 동작하도록 한다.
                LPWSTR s = nullptr;
                if (SUCCEEDED(args->TryGetWebMessageAsString(&s)) && s) {
                    cb(user, s);
                    CoTaskMemFree(s);
                }
            }
            return S_OK;
        });

    EventRegistrationToken token{};
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->add_WebMessageReceived(handler.Get(), &token));
}

extern "C" int32_t KSWV2_PostWebMessageAsJson(
    KSWV2WebView webview, const wchar_t *json_utf16)
{
    if (!webview || !json_utf16) return E_POINTER;
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->PostWebMessageAsJson(json_utf16));
}

extern "C" int32_t KSWV2_ExecuteScript(
    KSWV2WebView webview, const wchar_t *script_utf16)
{
    if (!webview || !script_utf16) return E_POINTER;
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->ExecuteScript(script_utf16, nullptr));
}

extern "C" int32_t KSWV2_OpenDevTools(KSWV2WebView webview) {
    if (!webview) return E_POINTER;
    return static_cast<int32_t>(KSWV2_AsWebView(webview)->OpenDevToolsWindow());
}

extern "C" int32_t KSWV2_SetDevToolsEnabled(KSWV2WebView webview, int32_t enabled) {
    if (!webview) return E_POINTER;
    ICoreWebView2Settings *settings = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->get_Settings(&settings);
    if (FAILED(hr) || !settings) return static_cast<int32_t>(hr);
    hr = settings->put_AreDevToolsEnabled(enabled ? TRUE : FALSE);
    settings->Release();
    return static_cast<int32_t>(hr);
}

extern "C" int32_t KSWV2_SetDefaultContextMenusEnabled(
    KSWV2WebView webview, int32_t enabled)
{
    if (!webview) return E_POINTER;
    ICoreWebView2Settings *settings = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->get_Settings(&settings);
    if (FAILED(hr) || !settings) return static_cast<int32_t>(hr);
    hr = settings->put_AreDefaultContextMenusEnabled(enabled ? TRUE : FALSE);
    settings->Release();
    return static_cast<int32_t>(hr);
}

/// WebView-level external-drop flag is a no-op stub kept for ABI compat;
/// the real toggle lives on the controller (`ICoreWebView2Controller4`).
extern "C" int32_t KSWV2_SetAllowExternalDrop(
    KSWV2WebView webview, int32_t allow)
{
    (void)webview; (void)allow;
    return 0;
}

extern "C" int32_t KSWV2_AddScriptToExecuteOnDocumentCreated(
    KSWV2WebView webview, const wchar_t *script_utf16)
{
    if (!webview || !script_utf16) return E_POINTER;
    // id는 필요하지 않음 — Swift는 webview를 재생성해 스크립을 제거한다.
    auto handler = Callback<
        ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
        [](HRESULT, LPCWSTR) -> HRESULT { return S_OK; });
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->AddScriptToExecuteOnDocumentCreated(
            script_utf16, handler.Get()));
}

extern "C" int32_t KSWV2_AddNavigationCompletedHandler(
    KSWV2WebView webview, void *user, KSWV2NavigationCompletedCB cb)
{
    if (!webview || !cb) return E_POINTER;

    auto handler = Callback<ICoreWebView2NavigationCompletedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2NavigationCompletedEventArgs *args) -> HRESULT {
            BOOL success = FALSE;
            args->get_IsSuccess(&success);
            COREWEBVIEW2_WEB_ERROR_STATUS status = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
            args->get_WebErrorStatus(&status);
            cb(user, static_cast<int32_t>(status),
               success ? 1 : 0);
            return S_OK;
        });

    EventRegistrationToken token{};
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->add_NavigationCompleted(handler.Get(), &token));
}

extern "C" int32_t KSWV2_SetVirtualHostNameToFolderMapping(
    KSWV2WebView webview,
    const wchar_t *host_name,
    const wchar_t *folder_path,
    int32_t access_kind)
{
    if (!webview || !host_name || !folder_path) return E_POINTER;
    ICoreWebView2_3 *wv3 = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->QueryInterface(
        IID_PPV_ARGS(&wv3));
    if (FAILED(hr) || !wv3) return static_cast<int32_t>(hr);
    COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND kind =
        COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY;
    switch (access_kind) {
        case 1: kind = COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW; break;
        case 2: kind = COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS; break;
        default: kind = COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY; break;
    }
    hr = wv3->SetVirtualHostNameToFolderMapping(
        host_name, folder_path, kind);
    wv3->Release();
    return static_cast<int32_t>(hr);
}
