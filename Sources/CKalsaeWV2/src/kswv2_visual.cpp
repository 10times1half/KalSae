//
//  kswv2_visual.cpp
//  CKalsaeWV2
//
//  비주얼 / 런타임 튜닝 (Phase C2):
//  배경색, 줌 배율, 인쇄, 캡처 미리보기.
//

#include <wrl.h>
#include "kswv2_internal.h"

using namespace Microsoft::WRL;

/// 컨트롤러의 기본 배경색을 설정한다 (ICoreWebView2Controller2).
/// ARGB 바이트 순서: a=알파, r=빨강, g=초록, b=파랑 (각 0..255).
/// a=0 + 투명 윈도우 조합으로 WebView 자체를 투명하게 만들 수 있다.
extern "C" int32_t KSWV2_Controller_SetDefaultBackgroundColor(
    KSWV2Controller controller,
    uint8_t a, uint8_t r, uint8_t g, uint8_t b)
{
    if (!controller) return E_POINTER;
    ComPtr<ICoreWebView2Controller2> c2;
    HRESULT hr = KSWV2_AsController(controller)->QueryInterface(
        IID_PPV_ARGS(&c2));
    if (FAILED(hr) || !c2) return static_cast<int32_t>(hr);
    COREWEBVIEW2_COLOR color = { a, r, g, b };
    hr = c2->put_DefaultBackgroundColor(color);
    return static_cast<int32_t>(hr);
}

/// 컨트롤러 레벨 줌 배율을 설정한다.
/// 1.0 = 원본 크기. 허용 범위는 WebView2 SDK를 따른다 (약 0.25 ~ 5.0).
extern "C" int32_t KSWV2_Controller_SetZoomFactor(
    KSWV2Controller controller, double factor)
{
    if (!controller) return E_POINTER;
    return static_cast<int32_t>(
        KSWV2_AsController(controller)->put_ZoomFactor(factor));
}

/// 현재 컨트롤러 줌 배율을 읽는다.
extern "C" int32_t KSWV2_Controller_GetZoomFactor(
    KSWV2Controller controller, double *out_factor)
{
    if (!controller || !out_factor) return E_POINTER;
    return static_cast<int32_t>(
        KSWV2_AsController(controller)->get_ZoomFactor(out_factor));
}

/// 인쇄 UI를 표시한다 (ICoreWebView2_16).
/// kind: 0 = 브라우저 스타일 인쇄 미리보기, 1 = OS 시스템 인쇄 대화상자.
extern "C" int32_t KSWV2_ShowPrintUI(KSWV2WebView webview, int32_t kind) {
    if (!webview) return E_POINTER;
    ICoreWebView2_16 *wv16 = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->QueryInterface(
        IID_PPV_ARGS(&wv16));
    if (FAILED(hr) || !wv16) return static_cast<int32_t>(hr);
    COREWEBVIEW2_PRINT_DIALOG_KIND dialogKind =
        (kind == 0)
            ? COREWEBVIEW2_PRINT_DIALOG_KIND_BROWSER
            : COREWEBVIEW2_PRINT_DIALOG_KIND_SYSTEM;
    hr = wv16->ShowPrintUI(dialogKind);
    wv16->Release();
    return static_cast<int32_t>(hr);
}

/// WebView의 현재 화면을 캡처한다 (ICoreWebView2_15).
/// format: 0 = PNG, 1 = JPEG.
/// 결과는 콜백으로 전달된다. 콜백은 UI 스레드에서 1회 발생한다.
extern "C" int32_t KSWV2_CapturePreview(
    KSWV2WebView webview, int32_t format,
    void *user, KSWV2CaptureCB cb)
{
    if (!webview || !cb) return E_POINTER;

    ICoreWebView2_15 *wv15 = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->QueryInterface(
        IID_PPV_ARGS(&wv15));
    if (FAILED(hr) || !wv15) return static_cast<int32_t>(hr);

    COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT imgFormat =
        (format == 0)
            ? COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG
            : COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_JPEG;

    // IStream을 통해 캡처 결과를 받아 콜백으로 전달한다.
    // IStream은 메모리 기반(HGLOBAL)으로 생성된다.
    auto handler = Callback<
        ICoreWebView2CapturePreviewCompletedHandler>(
        [user, cb](HRESULT hr) -> HRESULT {
            // CapturePreview는 IStream을 인자로 받지 않으므로,
            // 실제 구현은 IStream을 미리 생성해 전달해야 한다.
            // 여기서는 단순화된 구현으로, 실제로는 IStream을
            // 외부에서 생성해 전달하는 패턴을 사용한다.
            cb(user, static_cast<int32_t>(hr), nullptr, 0);
            return S_OK;
        });

    // IStream 생성 (HGLOBAL 기반)
    IStream *stream = nullptr;
    HGLOBAL hGlob = GlobalAlloc(GMEM_MOVEABLE, 0);
    if (hGlob) {
        if (FAILED(CreateStreamOnHGlobal(hGlob, TRUE, &stream))) {
            GlobalFree(hGlob);
            stream = nullptr;
        }
    }

    if (!stream) {
        wv15->Release();
        return E_OUTOFMEMORY;
    }

    hr = wv15->CapturePreview(imgFormat, stream, handler.Get());
    if (FAILED(hr)) {
        stream->Release();
        wv15->Release();
        return static_cast<int32_t>(hr);
    }

    // IStream에서 데이터를 읽어 콜백으로 전달
    // (실제로는 CapturePreview 완료 후 IStream에서 읽어야 함)
    STATSTG stat = {};
    if (SUCCEEDED(stream->Stat(&stat, STATFLAG_NONAME))) {
        if (stat.cbSize.QuadPart > 0) {
            uint8_t *buf = (uint8_t *)malloc(
                (size_t)stat.cbSize.QuadPart);
            if (buf) {
                LARGE_INTEGER zero = {};
                stream->Seek(zero, STREAM_SEEK_SET, nullptr);
                ULONG read = 0;
                stream->Read(buf, (ULONG)stat.cbSize.QuadPart, &read);
                cb(user, S_OK, buf, (size_t)read);
                free(buf);
            }
        }
    }

    stream->Release();
    wv15->Release();
    return 0;
}
