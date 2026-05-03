//
//  kswv2_taskbar.cpp
//  CKalsaeWV2
//
//  ITaskbarList3 래퍼 구현.
//  COM 초기화는 호출 측(`KSWindowsWindowBackend+Taskbar.swift`)이 책임진다.
//

#ifndef UNICODE
#  define UNICODE
#endif
#ifndef _UNICODE
#  define _UNICODE
#endif

#include <windows.h>
#include <shobjidl_core.h>
#include <wrl.h>
#include "kswv2_taskbar.h"

using Microsoft::WRL::ComPtr;

namespace {

/// ITaskbarList3 인스턴스를 얻는다.
/// COM은 이미 초기화되어 있다고 가정한다.
HRESULT GetTaskbarList(ComPtr<ITaskbarList3> &out) {
    ComPtr<ITaskbarList3> tbl;
    HRESULT hr = CoCreateInstance(
        CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&tbl));
    if (FAILED(hr)) return hr;
    hr = tbl->HrInit();
    if (FAILED(hr)) return hr;
    out = tbl;
    return S_OK;
}

/// KSTaskbarProgress 인덱스를 TBPFLAG로 변환한다.
/// 0 = none, 1 = indeterminate, 2 = normal, 3 = error, 4 = paused
TBPFLAG StateToFlag(int32_t state) {
    switch (state) {
    case 1:  return TBPF_INDETERMINATE;
    case 2:  return TBPF_NORMAL;
    case 3:  return TBPF_ERROR;
    case 4:  return TBPF_PAUSED;
    default: return TBPF_NOPROGRESS;
    }
}

} // namespace

extern "C" int32_t KSWV2_SetTaskbarProgress(HWND hwnd, KSWV2_TaskbarState state, uint32_t value) {
    if (!hwnd) return E_INVALIDARG;
    ComPtr<ITaskbarList3> tbl;
    HRESULT hr = GetTaskbarList(tbl);
    if (FAILED(hr)) return hr;

    TBPFLAG flag = StateToFlag(state);
    hr = tbl->SetProgressState(hwnd, flag);
    if (FAILED(hr)) return hr;

    if (flag == TBPF_NORMAL || flag == TBPF_ERROR || flag == TBPF_PAUSED) {
        // value는 0–100 범위; ITaskbarList3는 completed/total 쌍을 받는다.
        ULONGLONG clamped = (value > 100u) ? 100u : value;
        hr = tbl->SetProgressValue(hwnd, clamped, 100);
    }
    return hr;
}

extern "C" int32_t KSWV2_SetOverlayIcon(
    HWND hwnd, const wchar_t *iconPath, const wchar_t *description)
{
    if (!hwnd) return E_INVALIDARG;
    ComPtr<ITaskbarList3> tbl;
    HRESULT hr = GetTaskbarList(tbl);
    if (FAILED(hr)) return hr;

    HICON hIcon = nullptr;
    if (iconPath && iconPath[0]) {
        // LR_LOADFROMFILE — 파일에서 아이콘 로드.
        hIcon = static_cast<HICON>(
            LoadImageW(nullptr, iconPath, IMAGE_ICON, 16, 16, LR_LOADFROMFILE));
        if (!hIcon) return HRESULT_FROM_WIN32(GetLastError());
    }

    hr = tbl->SetOverlayIcon(hwnd, hIcon, description);
    if (hIcon) DestroyIcon(hIcon);
    return hr;
}
