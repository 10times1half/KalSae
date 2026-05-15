//
//  kswv2_webview.cpp
//  CKalsaeWV2
//
//  WebView 레벨 작업: 탐색, 메시지 핸들러, 설정 토글,
//  가상 호스트 매핑, 문서 생성 시 실행 스크립트 등록.
//

#include <wrl.h>
#include <objbase.h>
#include "kswv2_internal.h"

using namespace Microsoft::WRL;

/// WebView를 지정된 URL로 탐색한다.
extern "C" int32_t KSWV2_Navigate(KSWV2WebView webview, const wchar_t *url) {
    if (!webview || !url) return E_POINTER;
    return static_cast<int32_t>(KSWV2_AsWebView(webview)->Navigate(url));
}

/// WebMessageReceived 이벤트 핸들러를 등록한다.
/// WebView 측에서 `window.chrome.webview.postMessage(data)`를 호출하면
/// 이 핸들러가 트리거된다. JSON 형식을 우선 처리하고, 실패 시
/// 문자열 폴백(`TryGetWebMessageAsString`)을 시도한다.
extern "C" int32_t KSWV2_AddMessageHandler(
    KSWV2WebView webview, void *user, KSWV2MessageCB cb)
{
    if (!webview || !cb) return E_POINTER;

    auto handler = Callback<ICoreWebView2WebMessageReceivedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2WebMessageReceivedEventArgs *args) -> HRESULT {
            // JSON 형식 우선: postMessage({key: "value"}) 등 구조화된 데이터 처리
            LPWSTR json = nullptr;
            HRESULT hr = args->get_WebMessageAsJson(&json);
            if (SUCCEEDED(hr) && json) {
                cb(user, json);
                CoTaskMemFree(json);
            } else {
                // 문자열 폴백: postMessage("hi") 같은 단순 문자열도 처리
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

/// WebView로 JSON 메시지를 전송한다.
/// WebView 측에서는 `window.chrome.webview.addEventListener('message', handler)`로
/// 수신한다.
extern "C" int32_t KSWV2_PostWebMessageAsJson(
    KSWV2WebView webview, const wchar_t *json_utf16)
{
    if (!webview || !json_utf16) return E_POINTER;
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->PostWebMessageAsJson(json_utf16));
}

/// WebView에서 JavaScript 코드를 실행한다. 실행 결과는 무시된다.
/// 결과가 필요하면 PostWebMessageAsJson으로 요청/응답 패턴을 사용한다.
extern "C" int32_t KSWV2_ExecuteScript(
    KSWV2WebView webview, const wchar_t *script_utf16)
{
    if (!webview || !script_utf16) return E_POINTER;
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->ExecuteScript(script_utf16, nullptr));
}

/// WebView2 DevTools 창을 연다.
extern "C" int32_t KSWV2_OpenDevTools(KSWV2WebView webview) {
    if (!webview) return E_POINTER;
    return static_cast<int32_t>(KSWV2_AsWebView(webview)->OpenDevToolsWindow());
}

/// DevTools 활성화/비활성화. 첫 번째 탐색 전에 호출해야 초기 문서에 적용된다.
extern "C" int32_t KSWV2_SetDevToolsEnabled(KSWV2WebView webview, int32_t enabled) {
    if (!webview) return E_POINTER;
    ICoreWebView2Settings *settings = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->get_Settings(&settings);
    if (FAILED(hr) || !settings) return static_cast<int32_t>(hr);
    hr = settings->put_AreDevToolsEnabled(enabled ? TRUE : FALSE);
    settings->Release();
    return static_cast<int32_t>(hr);
}

/// WebView2 기본 컨텍스트 메뉴 활성화/비활성화.
/// DevTools와 독립적으로 제어된다.
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

/// WebView 레벨 외부 드롭 플래그는 ABI 호환성을 위한 빈 스텁이다.
/// 실제 토글은 컨트롤러(ICoreWebView2Controller4)에 있는
/// KSWV2_Controller_SetAllowExternalDrop을 사용해야 한다.
extern "C" int32_t KSWV2_SetAllowExternalDrop(
    KSWV2WebView webview, int32_t allow)
{
    (void)webview; (void)allow;
    return 0;
}

/// 문서 생성 시 실행할 JavaScript를 등록한다.
/// 이후 모든 탐색에서 이 스크립트가 자동으로 실행된다.
/// 등록된 스크립트 ID는 필요하지 않음 — Swift는 WebView를 재생성해
/// 스크립트를 제거한다.
extern "C" int32_t KSWV2_AddScriptToExecuteOnDocumentCreated(
    KSWV2WebView webview, const wchar_t *script_utf16)
{
    if (!webview || !script_utf16) return E_POINTER;
    auto handler = Callback<
        ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
        [](HRESULT, LPCWSTR) -> HRESULT { return S_OK; });
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->AddScriptToExecuteOnDocumentCreated(
            script_utf16, handler.Get()));
}

/// 탐색 완료 핸들러를 등록한다. 페이지 로딩이 완료될 때마다 호출된다.
/// is_success 외에도 WebErrorStatus를 함께 전달하여 오류 진단에 활용한다.
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

/// 가상 호스트 이름을 로컬 폴더에 매핑한다.
/// 예: "app.kalsae" → "C:/app/dist" 로 매핑하면
/// https://app.kalsae/index.html 로 로컬 파일에 접근할 수 있다.
/// ICoreWebView2_3 (런타임 1.0.864+) 필요.
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
