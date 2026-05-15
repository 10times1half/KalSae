//
//  kswv2_resource.cpp
//  CKalsaeWV2
//
//  WebResourceRequested 핸들러 + 필터 설치.
//  Swift 측 자산 리졸버에서 생성한 합성 HTTP 응답을 WebView2로 중계한다.
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

/// WebView에서 ICoreWebView2Environment를 얻는다.
/// ICoreWebView2_2로 QI한 후 get_Environment()를 호출한다.
ICoreWebView2Environment *GetEnvFromWebView(ICoreWebView2 *wv) {
    ICoreWebView2_2 *wv2 = nullptr;
    if (FAILED(wv->QueryInterface(IID_PPV_ARGS(&wv2))) || !wv2) return nullptr;
    ICoreWebView2Environment *env = nullptr;
    HRESULT hr = wv2->get_Environment(&env);
    wv2->Release();
    return SUCCEEDED(hr) ? env : nullptr;
}

// WebView별 Cross-Origin Isolation 플래그 저장소.
// KSWV2_SetCrossOriginIsolation으로 설정되며, 응답 헤더 빌더가 조회한다.
// 단순한 boolean이므로 mutex로 충분 (호출 빈도 매우 낮음).
std::mutex g_coi_mu;
std::unordered_map<ICoreWebView2 *, bool> g_coi_flags;

/// 주어진 WebView에 COI 플래그가 설정되어 있는지 조회한다.
bool LookupCOI(ICoreWebView2 *wv) {
    std::lock_guard<std::mutex> lock(g_coi_mu);
    auto it = g_coi_flags.find(wv);
    return it != g_coi_flags.end() && it->second;
}

} // namespace

/// Cross-Origin Isolation 헤더 자동 추가를 토글한다.
/// COOP/COEP/CORP 헤더를 모든 WebResourceRequested 응답에 추가한다.
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

/// 웹 리소스 요청 핸들러를 등록한다.
/// Swift 리졸버가 반환한 데이터로 IStream을 구성하고,
/// Content-Type, CSP, COI 등의 헤더를 조립하여 WebView2 응답을 생성한다.
extern "C" int32_t KSWV2_AddWebResourceRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2ResourceCB cb)
{
    if (!webview || !cb) return E_POINTER;
    ICoreWebView2 *wv = KSWV2_AsWebView(webview);

    auto handler = Callback<ICoreWebView2WebResourceRequestedEventHandler>(
        [user, cb](ICoreWebView2 *sender,
                   ICoreWebView2WebResourceRequestedEventArgs *args) -> HRESULT {
            // 요청 URI 추출
            ICoreWebView2WebResourceRequest *req = nullptr;
            if (FAILED(args->get_Request(&req)) || !req) return S_OK;
            LPWSTR uri = nullptr;
            req->get_Uri(&uri);
            req->Release();
            if (!uri) return S_OK;

            // Swift 리졸버 호출 — 데이터, Content-Type, CSP를 받아온다
            uint8_t *data = nullptr;
            size_t   len  = 0;
            wchar_t *ct   = nullptr;
            wchar_t *csp  = nullptr;
            int32_t rc = cb(user, uri, &data, &len, &ct, &csp);
            CoTaskMemFree(uri);
            if (rc != 0) {
                // 리졸버가 처리 거부 — WebView2가 기본 동작을 수행
                if (data) free(data);
                if (ct) free(ct);
                if (csp) free(csp);
                return S_OK;
            }

            // 데이터 버퍼로 IStream 구성 (HGLOBAL → CreateStreamOnHGlobal)
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

            // HTTP 응답 헤더 문자열 조립: "Name: Value\r\nName: Value" 형식
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
            // 보안 헤더: MIME 스니핑 방지 + Referrer 정책
            headers += L"X-Content-Type-Options: nosniff";
            headers += L"\r\nReferrer-Policy: no-referrer";
            // Cross-Origin Isolation 헤더 (선택적)
            if (LookupCOI(sender)) {
                headers += L"\r\nCross-Origin-Opener-Policy: same-origin";
                headers += L"\r\nCross-Origin-Embedder-Policy: require-corp";
                headers += L"\r\nCross-Origin-Resource-Policy: same-origin";
            }
            if (ct) free(ct);
            if (csp) free(csp);

            // WebView2 응답 생성
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

/// URI 와일드카드 패턴을 필터 목록에 추가한다.
/// 모든 웹 리소스 컨텍스트(문서, 스타일시트, 스크립트, 이미지 등)에 적용된다.
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
// Swift가 반환하는 응답 버퍼는 C++ 쪽에서 free()할 수 있어야 한다.
// Swift의 자체 할당자가 CRT 할당자와 일치한다는 보장이 없으므로, 콜백이
// 이 헬퍼를 통해 할당한다. 이는 shim이 링크한 같은 CRT의 malloc /
// _wcsdup을 그대로 감싼 것이다.

/// CRT malloc을 감싼 할당자. 0바이트 요청 시에도 최소 1바이트를 할당한다.
extern "C" void *KSWV2_Alloc(size_t n) {
    return malloc(n ? n : 1);
}

/// CRT free를 감싼 해제자. NULL 안전.
extern "C" void KSWV2_Free(void *p) {
    if (p) free(p);
}

/// 주어진 길이의 와이드 문자열을 CRT malloc으로 복사한다.
/// NUL 종료가 보장된다.
extern "C" wchar_t *KSWV2_WcsDupCopy(const wchar_t *src, size_t len) {
    wchar_t *dst = (wchar_t *)malloc((len + 1) * sizeof(wchar_t));
    if (!dst) return nullptr;
    if (src && len) memcpy(dst, src, len * sizeof(wchar_t));
    dst[len] = L'\0';
    return dst;
}
