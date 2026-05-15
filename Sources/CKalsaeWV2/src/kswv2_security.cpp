//
//  kswv2_security.cpp
//  CKalsaeWV2
//
//  보안 핸들러: 새 창(팝업), 권한 요청, 다운로드, 인증서 오류,
//  HTTP 기본 인증, 클라이언트 인증서 요청 처리.
//

#include <wrl.h>
#include "kswv2_internal.h"

using namespace Microsoft::WRL;

/// 새 창 요청 핸들러를 등록한다.
/// window.open() / target="_blank" 등으로 WebView2가 새 창을 열려할 때
/// 호출된다. 콜백이 0을 반환하면 요청을 거부한다.
extern "C" int32_t KSWV2_AddNewWindowRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2NewWindowCB cb)
{
    if (!webview || !cb) return E_POINTER;

    auto handler = Callback<ICoreWebView2NewWindowRequestedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2NewWindowRequestedEventArgs *args) -> HRESULT {
            LPWSTR uri = nullptr;
            args->get_Uri(&uri);
            int32_t deny = cb(user, uri ? uri : L"");
            if (uri) CoTaskMemFree(uri);
            if (deny == 0) {
                // 거부: Handled=TRUE, NewWindow=null로 설정
                args->put_Handled(TRUE);
                args->put_NewWindow(nullptr);
            }
            // 0이 아니면 허용 — WebView2가 기본 동작 수행
            return S_OK;
        });

    EventRegistrationToken token{};
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->add_NewWindowRequested(handler.Get(), &token));
}

/// 권한 요청 핸들러를 등록한다.
/// 마이크, 카메라, 지오로케이션 등 민감한 API 요청 시 호출된다.
/// 콜백 반환값: 0 = DENY, 1 = ALLOW, 2 = DEFAULT.
extern "C" int32_t KSWV2_AddPermissionRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2PermissionCB cb)
{
    if (!webview || !cb) return E_POINTER;

    auto handler = Callback<ICoreWebView2PermissionRequestedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2PermissionRequestedEventArgs *args) -> HRESULT {
            LPWSTR uri = nullptr;
            args->get_Uri(&uri);
            COREWEBVIEW2_PERMISSION_KIND kind;
            args->get_PermissionKind(&kind);
            int32_t decision = cb(user, uri ? uri : L"", static_cast<int32_t>(kind));
            if (uri) CoTaskMemFree(uri);
            COREWEBVIEW2_PERMISSION_STATE state =
                COREWEBVIEW2_PERMISSION_STATE_DEFAULT;
            switch (decision) {
                case 0: state = COREWEBVIEW2_PERMISSION_STATE_DENY; break;
                case 1: state = COREWEBVIEW2_PERMISSION_STATE_ALLOW; break;
                default: state = COREWEBVIEW2_PERMISSION_STATE_DEFAULT; break;
            }
            args->put_State(state);
            return S_OK;
        });

    EventRegistrationToken token{};
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->add_PermissionRequested(handler.Get(), &token));
}

/// 다운로드 시작 핸들러를 등록한다 (ICoreWebView2_4).
/// 페이지가 파일 다운로드를 시작할 때 호출된다.
/// 콜백 반환값: 0 = 허용, 1 = 취소.
extern "C" int32_t KSWV2_AddDownloadStartingHandler(
    KSWV2WebView webview, void *user, KSWV2DownloadStartingCB cb)
{
    if (!webview || !cb) return E_POINTER;

    ICoreWebView2_4 *wv4 = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->QueryInterface(IID_PPV_ARGS(&wv4));
    if (FAILED(hr) || !wv4) return static_cast<int32_t>(hr);

    auto handler = Callback<ICoreWebView2DownloadStartingEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2DownloadStartingEventArgs *args) -> HRESULT {
            ICoreWebView2DownloadOperation *op = nullptr;
            args->get_DownloadOperation(&op);
            if (!op) return S_OK;
            LPWSTR uri = nullptr;
            op->get_Uri(&uri);
            LPWSTR mime = nullptr;
            op->get_MimeType(&mime);
            int32_t cancel = cb(user, uri ? uri : L"", mime ? mime : L"");
            if (uri) CoTaskMemFree(uri);
            if (mime) CoTaskMemFree(mime);
            op->Release();
            args->put_Handled(TRUE);
            if (cancel != 0) {
                args->put_Cancel(TRUE);
            }
            return S_OK;
        });

    EventRegistrationToken token{};
    hr = wv4->add_DownloadStarting(handler.Get(), &token);
    wv4->Release();
    return static_cast<int32_t>(hr);
}

/// 서버 인증서 오류 핸들러를 등록한다 (ICoreWebView2_14).
/// TLS/서버 인증서 오류 시 호출된다.
/// 콜백 반환값: 0 = 취소, 1 = 계속(허용).
extern "C" int32_t KSWV2_AddServerCertificateErrorHandler(
    KSWV2WebView webview, void *user, KSWV2ServerCertErrorCB cb)
{
    if (!webview || !cb) return E_POINTER;

    ICoreWebView2_14 *wv14 = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->QueryInterface(IID_PPV_ARGS(&wv14));
    if (FAILED(hr) || !wv14) return static_cast<int32_t>(hr);

    auto handler = Callback<ICoreWebView2ServerCertificateErrorDetectedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2ServerCertificateErrorDetectedEventArgs *args) -> HRESULT {
            int32_t action = cb(user);
            if (action == 0) {
                args->put_Action(
                    COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_CANCEL);
            } else {
                args->put_Action(
                    COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_ALWAYS_ALLOW);
            }
            return S_OK;
        });

    EventRegistrationToken token{};
    hr = wv14->add_ServerCertificateErrorDetected(handler.Get(), &token);
    wv14->Release();
    return static_cast<int32_t>(hr);
}

/// HTTP 기본 인증 요청 핸들러를 등록한다 (ICoreWebView2_10).
/// 콜백 반환값: 0 = 취소, 1 = 계속(기본 처리).
extern "C" int32_t KSWV2_AddBasicAuthenticationHandler(
    KSWV2WebView webview, void *user, KSWV2BasicAuthCB cb)
{
    if (!webview || !cb) return E_POINTER;

    ICoreWebView2_10 *wv10 = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->QueryInterface(IID_PPV_ARGS(&wv10));
    if (FAILED(hr) || !wv10) return static_cast<int32_t>(hr);

    auto handler = Callback<ICoreWebView2BasicAuthenticationRequestedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2BasicAuthenticationRequestedEventArgs *args) -> HRESULT {
            LPWSTR uri = nullptr;
            args->get_Uri(&uri);
            ICoreWebView2BasicAuthenticationResponse *resp = nullptr;
            args->get_Response(&resp);
            LPWSTR challenge = nullptr;
            if (resp) {
                // challenge 문자열은 Response 인터페이스에서 얻을 수 없으므로
                // URI만 전달한다.
                (void)challenge;
            }
            int32_t cancel = cb(user, uri ? uri : L"", L"");
            if (uri) CoTaskMemFree(uri);
            if (cancel == 0) {
                args->put_Cancel(TRUE);
            }
            if (resp) resp->Release();
            return S_OK;
        });

    EventRegistrationToken token{};
    hr = wv10->add_BasicAuthenticationRequested(handler.Get(), &token);
    wv10->Release();
    return static_cast<int32_t>(hr);
}

/// 클라이언트 인증서 요청 핸들러를 등록한다 (ICoreWebView2_5).
/// 콜백 반환값: 0 = 취소, 1 = 기본 처리(OS 선택기).
extern "C" int32_t KSWV2_AddClientCertificateHandler(
    KSWV2WebView webview, void *user, KSWV2ClientCertCB cb)
{
    if (!webview || !cb) return E_POINTER;

    ICoreWebView2_5 *wv5 = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->QueryInterface(IID_PPV_ARGS(&wv5));
    if (FAILED(hr) || !wv5) return static_cast<int32_t>(hr);

    auto handler = Callback<ICoreWebView2ClientCertificateRequestedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2ClientCertificateRequestedEventArgs *args) -> HRESULT {
            LPWSTR host = nullptr;
            args->get_Host(&host);
            int32_t cancel = cb(user, host ? host : L"");
            if (host) CoTaskMemFree(host);
            if (cancel == 0) {
                args->put_Handled(TRUE);
                args->put_Cancel(TRUE);
            }
            return S_OK;
        });

    EventRegistrationToken token{};
    hr = wv5->add_ClientCertificateRequested(handler.Get(), &token);
    wv5->Release();
    return static_cast<int32_t>(hr);
}
