//
//  ksimage.cpp
//  CKalsaeWV2
//
//  WIC(Windows Imaging Component) 기반 PNG ↔ DIB 변환기.
//  클립보드 이미지 입출력 경로에서 호출된다.
//
//  스레딩: 호출자가 COM을 초기화한 스레드에서 동작한다고 가정한다.
//  안전을 위해 함수마다 `CoIncrementMTAUsage` 폴백을 두지 않고, 호출
//  실패 시 HRESULT를 그대로 반환해 Swift 쪽 로깅에 맡긴다.
//

#include <windows.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include "kswv2.h"

using Microsoft::WRL::ComPtr;

namespace {

// PROCESS-WIDE WIC 팩토리. 첫 호출 시 만들어 두고 재사용한다.
// 멀티스레드 환경에서도 IWICImagingFactory는 일반적으로 free-threaded.
IWICImagingFactory *g_wic = nullptr;

HRESULT EnsureFactory() {
    if (g_wic) return S_OK;
    IWICImagingFactory *f = nullptr;
    HRESULT hr = CoCreateInstance(
        CLSID_WICImagingFactory,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&f));
    if (FAILED(hr)) return hr;
    g_wic = f; // 의도적으로 Release 안 함 — 프로세스 수명까지 유지.
    return S_OK;
}

// `KSWV2_Alloc`로 할당된 버퍼에 `src`의 `n`바이트를 복사해 반환.
uint8_t *DupBytes(const void *src, size_t n) {
    uint8_t *p = static_cast<uint8_t *>(KSWV2_Alloc(n));
    if (!p) return nullptr;
    std::memcpy(p, src, n);
    return p;
}

} // namespace

// MARK: - PNG → DIB (32-bpp BGRA, bottom-up)

extern "C" int32_t KSImage_PNGToDIB(
    const uint8_t *png_bytes, size_t png_size,
    uint8_t **out_data, size_t *out_size)
{
    if (!png_bytes || png_size == 0 || !out_data || !out_size) {
        return E_POINTER;
    }
    HRESULT hr = EnsureFactory();
    if (FAILED(hr)) return hr;

    // 입력 메모리를 IWICStream으로 감싼다.
    ComPtr<IWICStream> stream;
    hr = g_wic->CreateStream(&stream);
    if (FAILED(hr)) return hr;
    hr = stream->InitializeFromMemory(
        const_cast<BYTE *>(png_bytes), static_cast<DWORD>(png_size));
    if (FAILED(hr)) return hr;

    // PNG 디코더 생성.
    ComPtr<IWICBitmapDecoder> decoder;
    hr = g_wic->CreateDecoderFromStream(
        stream.Get(),
        nullptr,
        WICDecodeMetadataCacheOnLoad,
        &decoder);
    if (FAILED(hr)) return hr;

    ComPtr<IWICBitmapFrameDecode> frame;
    hr = decoder->GetFrame(0, &frame);
    if (FAILED(hr)) return hr;

    // 32-bpp BGRA(pre-multiplied 아님)로 변환.
    ComPtr<IWICFormatConverter> converter;
    hr = g_wic->CreateFormatConverter(&converter);
    if (FAILED(hr)) return hr;
    hr = converter->Initialize(
        frame.Get(),
        GUID_WICPixelFormat32bppBGRA,
        WICBitmapDitherTypeNone,
        nullptr,
        0.0,
        WICBitmapPaletteTypeCustom);
    if (FAILED(hr)) return hr;

    UINT w = 0, h = 0;
    hr = converter->GetSize(&w, &h);
    if (FAILED(hr)) return hr;
    if (w == 0 || h == 0) return E_INVALIDARG;

    // 합리적 상한(32K x 32K) — 정수 오버플로/거대 할당 방어.
    if (w > 32768u || h > 32768u) return E_OUTOFMEMORY;

    const UINT stride = w * 4u;
    const size_t pixelBytes = static_cast<size_t>(stride) * h;
    const size_t total = sizeof(BITMAPINFOHEADER) + pixelBytes;

    uint8_t *buf = static_cast<uint8_t *>(KSWV2_Alloc(total));
    if (!buf) return E_OUTOFMEMORY;

    auto *bih = reinterpret_cast<BITMAPINFOHEADER *>(buf);
    std::memset(bih, 0, sizeof(*bih));
    bih->biSize        = sizeof(BITMAPINFOHEADER);
    bih->biWidth       = static_cast<LONG>(w);
    // 양수 = bottom-up. 표준 CF_DIB 형태.
    bih->biHeight      = static_cast<LONG>(h);
    bih->biPlanes      = 1;
    bih->biBitCount    = 32;
    bih->biCompression = BI_RGB;
    bih->biSizeImage   = static_cast<DWORD>(pixelBytes);

    // WIC는 top-down으로 픽셀을 쓴다. CF_DIB는 bottom-up이 표준이므로
    // 한 행씩 뒤집어 쓴다.
    uint8_t *pixels = buf + sizeof(BITMAPINFOHEADER);
    // 임시 top-down 버퍼에 일단 받고 행을 뒤집어 복사.
    uint8_t *tmp = static_cast<uint8_t *>(std::malloc(pixelBytes));
    if (!tmp) {
        KSWV2_Free(buf);
        return E_OUTOFMEMORY;
    }
    hr = converter->CopyPixels(
        nullptr, stride,
        static_cast<UINT>(pixelBytes), tmp);
    if (FAILED(hr)) {
        std::free(tmp);
        KSWV2_Free(buf);
        return hr;
    }
    for (UINT y = 0; y < h; ++y) {
        std::memcpy(
            pixels + (h - 1u - y) * stride,
            tmp    + y * stride,
            stride);
    }
    std::free(tmp);

    *out_data = buf;
    *out_size = total;
    return S_OK;
}

// MARK: - DIB → PNG

extern "C" int32_t KSImage_DIBToPNG(
    const uint8_t *dib_bytes, size_t dib_size,
    uint8_t **out_data, size_t *out_size)
{
    if (!dib_bytes || dib_size < sizeof(BITMAPINFOHEADER) || !out_data || !out_size) {
        return E_POINTER;
    }
    HRESULT hr = EnsureFactory();
    if (FAILED(hr)) return hr;

    auto *bih = reinterpret_cast<const BITMAPINFOHEADER *>(dib_bytes);
    const DWORD headerSize = bih->biSize;
    if (headerSize < sizeof(BITMAPINFOHEADER) || headerSize > dib_size) {
        return E_INVALIDARG;
    }
    const LONG biWidth = bih->biWidth;
    const LONG biHeight = bih->biHeight;
    const WORD bpp = bih->biBitCount;
    const DWORD compression = bih->biCompression;

    if (biWidth <= 0 || biHeight == 0) return E_INVALIDARG;
    // 24/32-bpp BI_RGB 또는 BI_BITFIELDS만 다룬다. 그 외(JPEG/PNG
    // 인코딩된 DIB, 8-bpp 팔레트 등)는 일반 클립보드 이미지에서 드물다.
    if (compression != BI_RGB && compression != BI_BITFIELDS) {
        return E_NOTIMPL;
    }
    if (bpp != 24 && bpp != 32) return E_NOTIMPL;

    const bool topDown = (biHeight < 0);
    const UINT w = static_cast<UINT>(biWidth);
    const UINT h = static_cast<UINT>(topDown ? -biHeight : biHeight);
    if (w == 0 || h == 0) return E_INVALIDARG;
    if (w > 32768u || h > 32768u) return E_INVALIDARG;

    // BI_BITFIELDS면 마스크 3개가 헤더 뒤에 따라온다. 단 V4/V5
    // 헤더(`biSize >= sizeof(BITMAPV4HEADER)=108`)는 마스크가 헤더에
    // 포함돼 있어 추가로 따라오지 않는다.
    size_t masksSize = 0;
    if (compression == BI_BITFIELDS && headerSize < 108) {
        masksSize = sizeof(DWORD) * 3;
    }
    const size_t pixelOffset = headerSize + masksSize;
    if (pixelOffset > dib_size) return E_INVALIDARG;

    // DIB 행은 4바이트 정렬.
    const UINT srcStride = ((w * bpp + 31u) / 32u) * 4u;
    const size_t expectedPixelBytes = static_cast<size_t>(srcStride) * h;
    if (dib_size - pixelOffset < expectedPixelBytes) {
        return E_INVALIDARG;
    }
    const uint8_t *srcPixels = dib_bytes + pixelOffset;

    // WIC bitmap을 만든다. 24-bpp는 BGR, 32-bpp는 BGRA로 가정.
    const REFGUID fmt = (bpp == 24)
        ? GUID_WICPixelFormat24bppBGR
        : GUID_WICPixelFormat32bppBGRA;

    // bottom-up이면 top-down으로 뒤집은 임시 버퍼를 만든다.
    const uint8_t *feedPixels = srcPixels;
    uint8_t *flipped = nullptr;
    if (!topDown) {
        flipped = static_cast<uint8_t *>(std::malloc(expectedPixelBytes));
        if (!flipped) return E_OUTOFMEMORY;
        for (UINT y = 0; y < h; ++y) {
            std::memcpy(
                flipped + y * srcStride,
                srcPixels + (h - 1u - y) * srcStride,
                srcStride);
        }
        feedPixels = flipped;
    }

    ComPtr<IWICBitmap> bitmap;
    hr = g_wic->CreateBitmapFromMemory(
        w, h, fmt,
        srcStride,
        static_cast<UINT>(expectedPixelBytes),
        const_cast<BYTE *>(feedPixels),
        &bitmap);
    if (FAILED(hr)) {
        if (flipped) std::free(flipped);
        return hr;
    }

    // 메모리 백킹 IStream을 만들어 PNG 인코더에 연결한다.
    ComPtr<IStream> memStream;
    hr = CreateStreamOnHGlobal(nullptr, TRUE, &memStream);
    if (FAILED(hr)) {
        if (flipped) std::free(flipped);
        return hr;
    }

    ComPtr<IWICBitmapEncoder> encoder;
    hr = g_wic->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
    if (SUCCEEDED(hr)) hr = encoder->Initialize(memStream.Get(), WICBitmapEncoderNoCache);
    if (FAILED(hr)) {
        if (flipped) std::free(flipped);
        return hr;
    }

    ComPtr<IWICBitmapFrameEncode> frame;
    ComPtr<IPropertyBag2> props;
    hr = encoder->CreateNewFrame(&frame, &props);
    if (SUCCEEDED(hr)) hr = frame->Initialize(props.Get());
    if (SUCCEEDED(hr)) hr = frame->SetSize(w, h);
    WICPixelFormatGUID outFmt = (bpp == 24)
        ? GUID_WICPixelFormat24bppBGR
        : GUID_WICPixelFormat32bppBGRA;
    if (SUCCEEDED(hr)) hr = frame->SetPixelFormat(&outFmt);
    if (SUCCEEDED(hr)) hr = frame->WriteSource(bitmap.Get(), nullptr);
    if (SUCCEEDED(hr)) hr = frame->Commit();
    if (SUCCEEDED(hr)) hr = encoder->Commit();

    if (flipped) std::free(flipped);
    if (FAILED(hr)) return hr;

    // HGLOBAL을 꺼내 바이트를 복사.
    HGLOBAL hg = nullptr;
    hr = GetHGlobalFromStream(memStream.Get(), &hg);
    if (FAILED(hr)) return hr;
    const SIZE_T sz = GlobalSize(hg);
    void *src = GlobalLock(hg);
    if (!src) return E_FAIL;
    uint8_t *buf = DupBytes(src, sz);
    GlobalUnlock(hg);
    if (!buf) return E_OUTOFMEMORY;

    *out_data = buf;
    *out_size = sz;
    return S_OK;
}
