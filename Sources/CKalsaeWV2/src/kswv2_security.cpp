//
//  kswv2_security.cpp
//  CKalsaeWV2
//
//  보안 관련 WebView2 핸들러:
//    - NewWindowRequested        (팝업/새 탭 요청 차단)
//    - PermissionRequested       (마이크/카메라/지오로케이션 등 거부-기본값)
//    - DownloadStarting          (다운로드 시작 알림 + 선택적 취소)
//    - ServerCertificateError    (TLS 오류 — deny-secure 기본값)
//    - BasicAuthenticationRequested (HTTP 인증 — 기본 거부)
//    - ClientCertificateRequested   (클라이언트 인증서 — 기본 거부)
//

#include <wrl.h>
#include <objbase.h>
#include "kswv2_internal.h"

using namespace Microsoft::WRL;

// ---------------------------------------------------------------------------
// MARK: - NewWindowRequested
// ---------------------------------------------------------------------------

extern "C" int32_t KSWV2_AddNewWindowRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2NewWindowCB cb)
{
    if (!webview || !cb) return E_POINTER;

    auto handler = Callback<ICoreWebView2NewWindowRequestedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2NewWindowRequestedEventArgs *args) -> HRESULT {
            LPWSTR uri = nullptr;
            if (SUCCEEDED(args->get_Uri(&uri)) && uri) {
                int32_t allow = cb(user, uri);
                CoTaskMemFree(uri);
                if (!allow) {
                    // 요청을 처리된 것으로 표시하고 새 창을 null로 설정해
                    // WebView2가 자체적으로 팝업을 열지 못하도록 한다.
                    args->put_Handled(TRUE);
                    args->put_NewWindow(nullptr);
                }
            } else {
                // URI를 읽을 수 없는 경우 안전을 위해 거부한다.
                if (uri) CoTaskMemFree(uri);
                args->put_Handled(TRUE);
                args->put_NewWindow(nullptr);
            }
            return S_OK;
        });

    EventRegistrationToken token{};
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->add_NewWindowRequested(handler.Get(), &token));
}

// ---------------------------------------------------------------------------
// MARK: - PermissionRequested
// ---------------------------------------------------------------------------

extern "C" int32_t KSWV2_AddPermissionRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2PermissionCB cb)
{
    if (!webview || !cb) return E_POINTER;

    auto handler = Callback<ICoreWebView2PermissionRequestedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2PermissionRequestedEventArgs *args) -> HRESULT {
            LPWSTR uri = nullptr;
            COREWEBVIEW2_PERMISSION_KIND kind = COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION;
            args->get_Uri(&uri);
            args->get_PermissionKind(&kind);
            int32_t result = cb(user, uri ? uri : L"", static_cast<int32_t>(kind));
            if (uri) CoTaskMemFree(uri);
            switch (result) {
            case 1:  args->put_State(COREWEBVIEW2_PERMISSION_STATE_ALLOW);   break;
            case 2:  args->put_State(COREWEBVIEW2_PERMISSION_STATE_DEFAULT);  break;
            default: args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);    break;
            }
            return S_OK;
        });

    EventRegistrationToken token{};
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->add_PermissionRequested(handler.Get(), &token));
}

// ---------------------------------------------------------------------------
// MARK: - DownloadStarting  (ICoreWebView2_4)
// ---------------------------------------------------------------------------

extern "C" int32_t KSWV2_AddDownloadStartingHandler(
    KSWV2WebView webview, void *user, KSWV2DownloadStartingCB cb)
{
    if (!webview || !cb) return E_POINTER;

    // DownloadStarting은 ICoreWebView2_4에 있다. QI로 업캐스트.
    ComPtr<ICoreWebView2_4> wv4;
    HRESULT qiHr = KSWV2_AsWebView(webview)->QueryInterface(IID_PPV_ARGS(&wv4));
    if (FAILED(qiHr)) return static_cast<int32_t>(qiHr);

    auto handler = Callback<ICoreWebView2DownloadStartingEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2DownloadStartingEventArgs *args) -> HRESULT {
            ComPtr<ICoreWebView2DownloadOperation> dlOp;
            LPWSTR url = nullptr;
            LPWSTR mime = nullptr;

            if (SUCCEEDED(args->get_DownloadOperation(&dlOp)) && dlOp) {
                dlOp->get_Uri(&url);
                dlOp->get_MimeType(&mime);
            }

            int32_t cancel = cb(user,
                url  ? url  : L"",
                mime ? mime : L"");

            if (url)  CoTaskMemFree(url);
            if (mime) CoTaskMemFree(mime);

            if (cancel) {
                args->put_Cancel(TRUE);
            }
            return S_OK;
        });

    EventRegistrationToken token{};
    return static_cast<int32_t>(wv4->add_DownloadStarting(handler.Get(), &token));
}

// ---------------------------------------------------------------------------
// MARK: - ServerCertificateErrorDetected  (ICoreWebView2_14)
// ---------------------------------------------------------------------------

extern "C" int32_t KSWV2_AddServerCertificateErrorHandler(
    KSWV2WebView webview, void *user, KSWV2ServerCertErrorCB cb)
{
    if (!webview || !cb) return E_POINTER;

    ComPtr<ICoreWebView2_14> wv14;
    HRESULT qiHr = KSWV2_AsWebView(webview)->QueryInterface(IID_PPV_ARGS(&wv14));
    if (FAILED(qiHr)) return static_cast<int32_t>(qiHr);  // E_NOINTERFACE on old runtimes

    auto handler = Callback<ICoreWebView2ServerCertificateErrorDetectedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2ServerCertificateErrorDetectedEventArgs *args) -> HRESULT {
            int32_t allow = cb(user);
            if (!allow) {
                // deny-secure: 탐색을 취소하고 빈 페이지로 이동.
                args->put_Action(COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_CANCEL);
            } else {
                args->put_Action(COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_ALWAYS_ALLOW);
            }
            return S_OK;
        });

    EventRegistrationToken token{};
    return static_cast<int32_t>(wv14->add_ServerCertificateErrorDetected(handler.Get(), &token));
}

// ---------------------------------------------------------------------------
// MARK: - BasicAuthenticationRequested  (ICoreWebView2_10)
// ---------------------------------------------------------------------------

extern "C" int32_t KSWV2_AddBasicAuthenticationHandler(
    KSWV2WebView webview, void *user, KSWV2BasicAuthCB cb)
{
    if (!webview || !cb) return E_POINTER;

    ComPtr<ICoreWebView2_10> wv10;
    HRESULT qiHr = KSWV2_AsWebView(webview)->QueryInterface(IID_PPV_ARGS(&wv10));
    if (FAILED(qiHr)) return static_cast<int32_t>(qiHr);

    auto handler = Callback<ICoreWebView2BasicAuthenticationRequestedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2BasicAuthenticationRequestedEventArgs *args) -> HRESULT {
            LPWSTR uri = nullptr;
            LPWSTR challenge = nullptr;
            args->get_Uri(&uri);
            if (SUCCEEDED(args->get_Challenge(&challenge)) == FALSE) {
                challenge = nullptr;
            }

            int32_t allow = cb(user,
                uri       ? uri       : L"",
                challenge ? challenge : L"");

            if (uri)       CoTaskMemFree(uri);
            if (challenge) CoTaskMemFree(challenge);

            // 0 = 취소(기본값). Cancel=TRUE → 인증 없이 실패.
            args->put_Cancel(!allow ? TRUE : FALSE);
            return S_OK;
        });

    EventRegistrationToken token{};
    return static_cast<int32_t>(wv10->add_BasicAuthenticationRequested(handler.Get(), &token));
}

// ---------------------------------------------------------------------------
// MARK: - ClientCertificateRequested  (ICoreWebView2_5)
// ---------------------------------------------------------------------------

extern "C" int32_t KSWV2_AddClientCertificateHandler(
    KSWV2WebView webview, void *user, KSWV2ClientCertCB cb)
{
    if (!webview || !cb) return E_POINTER;

    ComPtr<ICoreWebView2_5> wv5;
    HRESULT qiHr = KSWV2_AsWebView(webview)->QueryInterface(IID_PPV_ARGS(&wv5));
    if (FAILED(qiHr)) return static_cast<int32_t>(qiHr);

    auto handler = Callback<ICoreWebView2ClientCertificateRequestedEventHandler>(
        [user, cb](ICoreWebView2 *,
                   ICoreWebView2ClientCertificateRequestedEventArgs *args) -> HRESULT {
            LPWSTR host = nullptr;
            args->get_Host(&host);

            int32_t allow = cb(user, host ? host : L"");
            if (host) CoTaskMemFree(host);

            if (!allow) {
                // Cancel=TRUE, Handled=TRUE → 인증서 없이 진행 (서버가 거부).
                args->put_Cancel(TRUE);
                args->put_Handled(TRUE);
            }
            return S_OK;
        });

    EventRegistrationToken token{};
    return static_cast<int32_t>(wv5->add_ClientCertificateRequested(handler.Get(), &token));
}

