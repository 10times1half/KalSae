//
//  kswv2_resource.cpp
//  CKalsaeWV2
//
//  WebResourceRequested handler + filter installation. Bridges synthetic
//  HTTP responses from the Swift-side asset resolver back to WebView2.
//

#include <wrl.h>
#include <objbase.h>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include "kswv2_internal.h"

using namespace Microsoft::WRL;

namespace {

// 응답 생성에 필요하므로 webview에서 환경을 꺼낸다.
ICoreWebView2Environment *GetEnvFromWebView(ICoreWebView2 *wv) {
    ICoreWebView2_2 *wv2 = nullptr;
    if (FAILED(wv->QueryInterface(IID_PPV_ARGS(&wv2))) || !wv2) return nullptr;
    ICoreWebView2Environment *env = nullptr;
    HRESULT hr = wv2->get_Environment(&env);
    wv2->Release();
    return SUCCEEDED(hr) ? env : nullptr;
}

// webview 별 Cross-Origin Isolation 플래그 저장소.
// `KSWV2_SetCrossOriginIsolation`로 설정되며, 응답 헤더 빌더가 조회한다.
// 단순한 boolean이므로 mutex로 충분 (호출 빈도 매우 낮음).
std::mutex g_coi_mu;
std::unordered_map<ICoreWebView2 *, bool> g_coi_flags;

bool LookupCOI(ICoreWebView2 *wv) {
    std::lock_guard<std::mutex> lock(g_coi_mu);
    auto it = g_coi_flags.find(wv);
    return it != g_coi_flags.end() && it->second;
}

} // namespace

extern "C" int32_t KSWV2_SetCrossOriginIsolation(
    KSWV2WebView webview, int32_t enabled)
{
    if (!webview) return E_POINTER;
    ICoreWebView2 *wv = KSWV2_AsWebView(webview);
    std::lock_guard<std::mutex> lock(g_coi_mu);
    if (enabled) {
        g_coi_flags[wv] = true;
    } else {
        g_coi_flags.erase(wv);
    }
    return 0;
}

extern "C" int32_t KSWV2_AddWebResourceRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2ResourceCB cb)
{
    if (!webview || !cb) return E_POINTER;
    ICoreWebView2 *wv = KSWV2_AsWebView(webview);

    auto handler = Callback<ICoreWebView2WebResourceRequestedEventHandler>(
        [user, cb](ICoreWebView2 *sender,
                   ICoreWebView2WebResourceRequestedEventArgs *args) -> HRESULT {
            // 요청 URI 추출.
            ICoreWebView2WebResourceRequest *req = nullptr;
            if (FAILED(args->get_Request(&req)) || !req) return S_OK;
            LPWSTR uri = nullptr;
            req->get_Uri(&uri);
            req->Release();
            if (!uri) return S_OK;

            // Swift 리졸버 호출.
            uint8_t *data = nullptr;
            size_t   len  = 0;
            wchar_t *ct   = nullptr;
            wchar_t *csp  = nullptr;
            int32_t rc = cb(user, uri, &data, &len, &ct, &csp);
            CoTaskMemFree(uri);
            if (rc != 0) {
                if (data) free(data);
                if (ct) free(ct);
                if (csp) free(csp);
                return S_OK;
            }

            // 호출자가 제공한 버퍼로 IStream 구성.
            IStream *stream = nullptr;
            HGLOBAL hGlob = GlobalAlloc(GMEM_MOVEABLE, len ? len : 1);
            if (hGlob) {
                if (len) {
                    void *p = GlobalLock(hGlob);
                    if (p) { memcpy(p, data, len); GlobalUnlock(hGlob); }
                }
                if (FAILED(CreateStreamOnHGlobal(hGlob, TRUE, &stream))) {
                    GlobalFree(hGlob);
                    stream = nullptr;
                }
            }
            if (data) free(data);
            if (!stream) {
                if (ct) free(ct);
                if (csp) free(csp);
                return S_OK;
            }

            // 헤더 문자열 조립: `Name: Value\r\nName: Value`.
            std::wstring headers;
            if (ct && ct[0]) {
                headers += L"Content-Type: ";
                headers += ct;
            }
            if (csp && csp[0]) {
                if (!headers.empty()) headers += L"\r\n";
                headers += L"Content-Security-Policy: ";
                headers += csp;
            }
            if (!headers.empty()) headers += L"\r\n";
            headers += L"X-Content-Type-Options: nosniff";
            headers += L"\r\nReferrer-Policy: no-referrer";
            if (LookupCOI(sender)) {
                headers += L"\r\nCross-Origin-Opener-Policy: same-origin";
                headers += L"\r\nCross-Origin-Embedder-Policy: require-corp";
                headers += L"\r\nCross-Origin-Resource-Policy: same-origin";
            }
            if (ct) free(ct);
            if (csp) free(csp);

            // 응답 생성.
            ICoreWebView2Environment *env = GetEnvFromWebView(sender);
            if (env) {
                ICoreWebView2WebResourceResponse *resp = nullptr;
                HRESULT hr = env->CreateWebResourceResponse(
                    stream, 200, L"OK",
                    headers.empty() ? nullptr : headers.c_str(),
                    &resp);
                env->Release();
                if (SUCCEEDED(hr) && resp) {
                    args->put_Response(resp);
                    resp->Release();
                }
            }
            stream->Release();
            return S_OK;
        });

    EventRegistrationToken token{};
    return static_cast<int32_t>(
        wv->add_WebResourceRequested(handler.Get(), &token));
}

extern "C" int32_t KSWV2_AddWebResourceRequestedFilter(
    KSWV2WebView webview, const wchar_t *uri_wildcard)
{
    if (!webview || !uri_wildcard) return E_POINTER;
    return static_cast<int32_t>(
        KSWV2_AsWebView(webview)->AddWebResourceRequestedFilter(
            uri_wildcard, COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL));
}

// MARK: - 메모리 할당 헬퍼
//
// Swift가 반환하는 응답 버퍼는 C++ 쪽에서 `free()`할 수 있어야 한다.
// Swift의 자체 할당자가 CRT 할당자와 일치한다는 보장이 없으므로, 콜백이
// 이 헬퍼를 통해 할당한다. 이는 쉬밌이 링크한 같은 CRT의 `malloc` /
// `_wcsdup`을 그대로 감싼 것이다.

extern "C" void *KSWV2_Alloc(size_t n) {
    return malloc(n ? n : 1);
}

extern "C" void KSWV2_Free(void *p) {
    if (p) free(p);
}

extern "C" wchar_t *KSWV2_WcsDupCopy(const wchar_t *src, size_t len) {
    wchar_t *dst = (wchar_t *)malloc((len + 1) * sizeof(wchar_t));
    if (!dst) return nullptr;
    if (src && len) memcpy(dst, src, len * sizeof(wchar_t));
    dst[len] = L'\0';
    return dst;
}
