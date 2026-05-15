//
//  kswv2_drop.cpp
//  CKalsaeWV2
//
//  네이티브 파일 드래그 앤 드롭 (IDropTarget).
//  WebView2의 AllowExternalDrop을 비활성화하고 호스트 HWND에
//  IDropTarget을 설치하여 OS 파일 드롭 이벤트를 가로챈다.
//

#include <wrl.h>
#include <ole2.h>
#include <shlobj.h>
#include <vector>
#include <string>
#include <unordered_map>
#include "kswv2_internal.h"

using namespace Microsoft::WRL;

namespace {

/// IDropTarget 구현 — COM 객체.
/// WebView2 자식이 파일 드롭을 소비하지 못하도록 하고,
/// 호스트 측에서 드롭 이벤트를 수신한다.
class DropTargetImpl : public RuntimeClass<
    RuntimeClassFlags<RuntimeClassType::ClassicCom>,
    IDropTarget>
{
public:
    DropTargetImpl(void *user, KSWV2DropCB cb)
        : m_user(user), m_cb(cb) {}

    // IDropTarget
    STDMETHODIMP DragEnter(
        IDataObject *pDataObj,
        DWORD grfKeyState,
        POINTL pt,
        DWORD *pdwEffect) override
    {
        if (!m_cb) {
            *pdwEffect = DROPEFFECT_NONE;
            return S_OK;
        }
        std::vector<std::wstring> paths;
        ExtractFilePaths(pDataObj, paths);
        std::vector<const wchar_t *> ptrs;
        for (auto &p : paths) ptrs.push_back(p.c_str());
        int32_t accept = m_cb(m_user,
            KSWV2_DropEvent_Enter,
            pt.x, pt.y,
            ptrs.data(), (int32_t)ptrs.size());
        *pdwEffect = accept == 0 ? DROPEFFECT_COPY : DROPEFFECT_NONE;
        return S_OK;
    }

    STDMETHODIMP DragOver(
        DWORD grfKeyState,
        POINTL pt,
        DWORD *pdwEffect) override
    {
        // DragEnter에서 결정한 효과를 유지
        // (간소화: 항상 COPY 또는 NONE)
        *pdwEffect = DROPEFFECT_COPY;
        return S_OK;
    }

    STDMETHODIMP DragLeave() override {
        if (m_cb) {
            m_cb(m_user, KSWV2_DropEvent_Leave, 0, 0, nullptr, 0);
        }
        return S_OK;
    }

    STDMETHODIMP Drop(
        IDataObject *pDataObj,
        DWORD grfKeyState,
        POINTL pt,
        DWORD *pdwEffect) override
    {
        if (!m_cb) {
            *pdwEffect = DROPEFFECT_NONE;
            return S_OK;
        }
        std::vector<std::wstring> paths;
        ExtractFilePaths(pDataObj, paths);
        std::vector<const wchar_t *> ptrs;
        for (auto &p : paths) ptrs.push_back(p.c_str());
        int32_t accept = m_cb(m_user,
            KSWV2_DropEvent_Drop,
            pt.x, pt.y,
            ptrs.data(), (int32_t)ptrs.size());
        *pdwEffect = accept == 0 ? DROPEFFECT_COPY : DROPEFFECT_NONE;
        return S_OK;
    }

private:
    void *m_user;
    KSWV2DropCB m_cb;

    /// IDataObject에서 CF_HDROP(파일 경로 목록)을 추출한다.
    static void ExtractFilePaths(
        IDataObject *pDataObj,
        std::vector<std::wstring> &outPaths)
    {
        if (!pDataObj) return;

        FORMATETC fmt = {
            CF_HDROP,
            nullptr,
            DVASPECT_CONTENT,
            -1,
            TYMED_HGLOBAL
        };
        STGMEDIUM med = {};
        if (FAILED(pDataObj->GetData(&fmt, &med))) return;

        HDROP hDrop = (HDROP)GlobalLock(med.hGlobal);
        if (!hDrop) {
            ReleaseStgMedium(&med);
            return;
        }

        UINT count = DragQueryFileW(hDrop, 0xFFFFFFFF, nullptr, 0);
        for (UINT i = 0; i < count; i++) {
            UINT len = DragQueryFileW(hDrop, i, nullptr, 0);
            if (len == 0) continue;
            std::wstring path(len + 1, L'\0');
            DragQueryFileW(hDrop, i, &path[0], len + 1);
            path.resize(len);
            outPaths.push_back(std::move(path));
        }

        GlobalUnlock(med.hGlobal);
        ReleaseStgMedium(&med);
    }
};

// 등록된 IDropTarget을 HWND별로 추적하는 맵
std::unordered_map<HWND, IDropTarget *> g_dropTargets;

} // namespace

/// OleInitialize를 호출 스레드에 대해 한 번 호출한다 (멱등성).
/// RegisterDragDrop 전에 필요하다.
extern "C" int32_t KSWV2_OleInitializeOnce(void) {
    HRESULT hr = OleInitialize(nullptr);
    if (hr == S_OK || hr == S_FALSE) return 0;
    return static_cast<int32_t>(hr);
}

/// HWND에 IDropTarget을 설치한다.
/// 이전에 등록된 드롭 타겟이 있으면 RevokeDragDrop 후 새로 등록한다.
extern "C" int32_t KSWV2_RegisterDropTarget(
    void *hwnd, void *user, KSWV2DropCB cb)
{
    if (!hwnd || !cb) return E_POINTER;
    HWND h = reinterpret_cast<HWND>(hwnd);

    // 기존 타겟 해제
    auto it = g_dropTargets.find(h);
    if (it != g_dropTargets.end()) {
        RevokeDragDrop(h);
        it->second->Release();
        g_dropTargets.erase(it);
    }

    // 새 IDropTarget 생성 (WRL Make로 생성, refcount 1에서 시작)
    auto target = Make<DropTargetImpl>(user, cb);
    if (!target) return E_OUTOFMEMORY;

    HRESULT hr = RegisterDragDrop(h, target.Get());
    if (FAILED(hr)) {
        return static_cast<int32_t>(hr);
    }

    // 맵에 소유권 저장을 위해 AddRef (g_dropTargets 해제 시 Release)
    target->AddRef();
    g_dropTargets[h] = target.Get();
    return 0;
}

/// HWND의 드롭 타겟을 해제한다.
extern "C" void KSWV2_RevokeDropTarget(void *hwnd) {
    if (!hwnd) return;
    HWND h = reinterpret_cast<HWND>(hwnd);
    auto it = g_dropTargets.find(h);
    if (it != g_dropTargets.end()) {
        RevokeDragDrop(h);
        it->second->Release();
        g_dropTargets.erase(it);
    }
}
