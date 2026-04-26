//
//  kswv2_capture.cpp
//  CKalsaeWV2
//
//  Phase D1 (ShowPrintUI) + Phase D3 (CapturePreview) shims. Both target
//  Wails-parity surfaces.
//
//   - ShowPrintUI 는 ICoreWebView2_16 가 필요하므로 QI 후에만 호출한다.
//   - CapturePreview 는 베이스 ICoreWebView2 인터페이스에서 바로 호출
//     가능하다. 결과는 IStream 으로 들어오며, 핸들러 안에서
//     `GetHGlobalFromStream`+`GlobalLock`으로 메모리에 매핑한 뒤 Swift
//     콜백으로 단 1회 전달한다. 콜백이 반환되면 즉시 unlock/release 한다.
//

#include <wrl.h>
#include <objbase.h>
#include "kswv2_internal.h"

using namespace Microsoft::WRL;

// MARK: - ShowPrintUI (D1)

extern "C" int32_t KSWV2_ShowPrintUI(KSWV2WebView webview, int32_t kind) {
    if (!webview) return E_POINTER;
    ICoreWebView2_16 *wv16 = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->QueryInterface(
        IID_PPV_ARGS(&wv16));
    if (FAILED(hr) || !wv16) return static_cast<int32_t>(hr);

    auto dialog = (kind == 1)
        ? COREWEBVIEW2_PRINT_DIALOG_KIND_SYSTEM
        : COREWEBVIEW2_PRINT_DIALOG_KIND_BROWSER;
    hr = wv16->ShowPrintUI(dialog);
    wv16->Release();
    return static_cast<int32_t>(hr);
}

// MARK: - CapturePreview (D3)

extern "C" int32_t KSWV2_CapturePreview(
    KSWV2WebView webview, int32_t format,
    void *user, KSWV2CaptureCB cb)
{
    if (!webview || !cb) return E_POINTER;

    IStream *stream = nullptr;
    HRESULT hr = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
    if (FAILED(hr) || !stream) return static_cast<int32_t>(hr);

    auto fmt = (format == 1)
        ? COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_JPEG
        : COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG;

    auto handler = Callback<ICoreWebView2CapturePreviewCompletedHandler>(
        [user, cb, stream](HRESULT result) -> HRESULT {
            if (FAILED(result)) {
                cb(user, static_cast<int32_t>(result), nullptr, 0);
                stream->Release();
                return S_OK;
            }
            HGLOBAL hg = nullptr;
            HRESULT gh = GetHGlobalFromStream(stream, &hg);
            if (FAILED(gh) || !hg) {
                cb(user, static_cast<int32_t>(gh), nullptr, 0);
                stream->Release();
                return S_OK;
            }
            SIZE_T len = GlobalSize(hg);
            void  *ptr = GlobalLock(hg);
            if (!ptr) {
                cb(user, E_FAIL, nullptr, 0);
                stream->Release();
                return S_OK;
            }
            cb(user, 0, static_cast<const uint8_t *>(ptr),
               static_cast<size_t>(len));
            GlobalUnlock(hg);
            stream->Release();
            return S_OK;
        });

    hr = KSWV2_AsWebView(webview)->CapturePreview(fmt, stream, handler.Get());
    if (FAILED(hr)) {
        stream->Release();
    }
    return static_cast<int32_t>(hr);
}
