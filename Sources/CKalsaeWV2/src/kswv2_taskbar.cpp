//
//  kswv2_taskbar.cpp
//  CKalsaeWV2
//
//  ITaskbarList3 래퍼 — 작업 표시줄 진행 상태 표시 및 오버레이 아이콘.
//  Windows 7 이상의 작업 표시줄 기능을 제공한다.
//

#include <wrl.h>
#include <shobjidl.h>
#include "kswv2_internal.h"
#include "kswv2_taskbar.h"

using namespace Microsoft::WRL;

// ITaskbarList3 싱글톤 (지연 초기화)
static ComPtr<ITaskbarList3> g_taskbar;

/// ITaskbarList3 인스턴스를 얻는다 (지연 초기화).
static ITaskbarList3 *GetTaskbar() {
    if (!g_taskbar) {
        ComPtr<ITaskbarList3> tb;
        HRESULT hr = CoCreateInstance(
            CLSID_TaskbarList,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&tb));
        if (SUCCEEDED(hr) && tb) {
            tb->HrInit();
            g_taskbar = tb;
        }
    }
    return g_taskbar.Get();
}

/// HWND의 작업 표시줄 진행 상태를 설정한다.
/// state: 0=NOPROGRESS, 1=INDETERMINATE, 2=NORMAL, 3=ERROR, 4=PAUSED
/// value: 진행률 (0–100). state가 0 또는 1이면 무시된다.
extern "C" int32_t KSWV2_SetTaskbarProgress(
    HWND hwnd, KSWV2_TaskbarState state, uint32_t value)
{
    if (!hwnd || !IsWindow(hwnd)) return E_INVALIDARG;

    ITaskbarList3 *tb = GetTaskbar();
    if (!tb) return E_FAIL;

    // TBPFLAG 값 매핑
    TBPFLAG flags = TBPF_NOPROGRESS;
    switch (state) {
        case 0: flags = TBPF_NOPROGRESS; break;
        case 1: flags = TBPF_INDETERMINATE; break;
        case 2: flags = TBPF_NORMAL; break;
        case 3: flags = TBPF_ERROR; break;
        case 4: flags = TBPF_PAUSED; break;
        default: flags = TBPF_NOPROGRESS; break;
    }

    HRESULT hr = tb->SetProgressState(hwnd, flags);
    if (FAILED(hr)) return static_cast<int32_t>(hr);

    // 진행률 설정 (NOPROGRESS/INDETERMINATE가 아닌 경우)
    if (state == 2 || state == 3 || state == 4) {
        ULONGLONG completed = value;
        ULONGLONG total = 100;
        hr = tb->SetProgressValue(hwnd, completed, total);
    }

    return static_cast<int32_t>(hr);
}

/// HWND의 작업 표시줄 오버레이 아이콘을 설정/해제한다.
/// iconPath: 아이콘 파일(.ico) 경로. NULL이면 기존 오버레이를 제거한다.
/// description: 접근성 설명 문자열. NULL 가능.
extern "C" int32_t KSWV2_SetOverlayIcon(
    HWND hwnd, const wchar_t *iconPath, const wchar_t *description)
{
    if (!hwnd || !IsWindow(hwnd)) return E_INVALIDARG;

    ITaskbarList3 *tb = GetTaskbar();
    if (!tb) return E_FAIL;

    HICON hIcon = nullptr;
    if (iconPath && *iconPath) {
        // 아이콘 파일 로드
        hIcon = (HICON)LoadImageW(
            nullptr,
            iconPath,
            IMAGE_ICON,
            16, 16,  // 작업 표시줄 오버레이 표준 크기
            LR_LOADFROMFILE);
        if (!hIcon) return HRESULT_FROM_WIN32(GetLastError());
    }

    HRESULT hr = tb->SetOverlayIcon(hwnd, hIcon, description);
    if (hIcon) DestroyIcon(hIcon);

    return static_cast<int32_t>(hr);
}
