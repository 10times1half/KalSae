//
//  kswv2_visual.cpp
//  CKalsaeWV2
//
//  Phase C2 — Visual / runtime tuning surfaces:
//   - Default background colour      (ICoreWebView2Controller2)
//   - Zoom factor                    (ICoreWebView2Controller)
//   - Pinch-zoom toggle              (ICoreWebView2Settings5)
//
//  All operations are no-ops returning E_NOINTERFACE on runtimes that
//  pre-date the relevant interface revision; callers ignore failures.
//

#include "kswv2_internal.h"

extern "C" int32_t KSWV2_Controller_SetDefaultBackgroundColor(
    KSWV2Controller controller,
    uint8_t a, uint8_t r, uint8_t g, uint8_t b)
{
    if (!controller) return E_POINTER;
    ICoreWebView2Controller2 *c2 = nullptr;
    HRESULT hr = KSWV2_AsController(controller)->QueryInterface(
        IID_PPV_ARGS(&c2));
    if (FAILED(hr) || !c2) return static_cast<int32_t>(hr);

    COREWEBVIEW2_COLOR color{};
    color.A = a; color.R = r; color.G = g; color.B = b;
    hr = c2->put_DefaultBackgroundColor(color);
    c2->Release();
    return static_cast<int32_t>(hr);
}

extern "C" int32_t KSWV2_Controller_SetZoomFactor(
    KSWV2Controller controller, double factor)
{
    if (!controller) return E_POINTER;
    return static_cast<int32_t>(
        KSWV2_AsController(controller)->put_ZoomFactor(factor));
}

extern "C" int32_t KSWV2_Controller_GetZoomFactor(
    KSWV2Controller controller, double *out_factor)
{
    if (!controller || !out_factor) return E_POINTER;
    double v = 1.0;
    HRESULT hr = KSWV2_AsController(controller)->get_ZoomFactor(&v);
    if (SUCCEEDED(hr)) *out_factor = v;
    return static_cast<int32_t>(hr);
}

extern "C" int32_t KSWV2_SetPinchZoomEnabled(
    KSWV2WebView webview, int32_t enabled)
{
    if (!webview) return E_POINTER;
    ICoreWebView2Settings *settings = nullptr;
    HRESULT hr = KSWV2_AsWebView(webview)->get_Settings(&settings);
    if (FAILED(hr) || !settings) return static_cast<int32_t>(hr);

    ICoreWebView2Settings5 *s5 = nullptr;
    hr = settings->QueryInterface(IID_PPV_ARGS(&s5));
    settings->Release();
    if (FAILED(hr) || !s5) return static_cast<int32_t>(hr);

    hr = s5->put_IsPinchZoomEnabled(enabled ? TRUE : FALSE);
    s5->Release();
    return static_cast<int32_t>(hr);
}
