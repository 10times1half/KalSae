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

/// 단일 HWND 에 IDropTarget 을 (재)등록하는 헬퍼.
/// 기존 타겟이 있으면 Revoke 후 재등록한다. 등록에 성공하면 g_dropTargets
/// 에 owning reference 를 보관해 추후 Revoke 시 Release 한다.
static HRESULT RegisterOnOne(HWND h, void *user, KSWV2DropCB cb) {
    auto it = g_dropTargets.find(h);
    if (it != g_dropTargets.end()) {
        RevokeDragDrop(h);
        it->second->Release();
        g_dropTargets.erase(it);
    }
    // WebView2 등 다른 컴포넌트가 이미 등록한 IDropTarget 이 있을 수 있으므로
    // 무조건 한 번 더 Revoke 해 둔다. (실패 무시)
    RevokeDragDrop(h);

    auto target = Make<DropTargetImpl>(user, cb);
    if (!target) return E_OUTOFMEMORY;

    HRESULT hr = RegisterDragDrop(h, target.Get());
    if (FAILED(hr)) return hr;

    target->AddRef();
    g_dropTargets[h] = target.Get();
    return S_OK;
}

namespace {
struct EnumCtx {
    void *user;
    KSWV2DropCB cb;
};

BOOL CALLBACK EnumChildRegisterProc(HWND child, LPARAM lp) {
    auto *ctx = reinterpret_cast<EnumCtx *>(lp);
    // 자식의 등록 실패는 무시 — 일부 child class 는 OleInitialize 되지 않은
    // 스레드에 속할 수 있다.
    (void)RegisterOnOne(child, ctx->user, ctx->cb);
    return TRUE;
}
}  // namespace

/// HWND 및 그 모든 자손 HWND 에 IDropTarget 을 설치한다.
///
/// WebView2 는 자체 child HWND 를 생성해 그 HWND 의 IDropTarget 으로 OS
/// 파일 드롭을 가로챈다. AllowExternalDrop=false 만으로는 WebView2 가
/// DROPEFFECT_NONE 을 반환해 X 커서가 유지되므로, 부모뿐 아니라 모든
/// 자식 HWND 에도 우리 IDropTarget 을 (재)등록한다.
extern "C" int32_t KSWV2_RegisterDropTarget(
    void *hwnd, void *user, KSWV2DropCB cb)
{
    if (!hwnd || !cb) return E_POINTER;
    HWND h = reinterpret_cast<HWND>(hwnd);

    HRESULT hr = RegisterOnOne(h, user, cb);
    if (FAILED(hr)) return static_cast<int32_t>(hr);

    // 모든 자식(및 그 자손)에 동일 핸들러 등록.
    // EnumChildWindows 는 재귀적으로 모든 자손을 방문한다.
    EnumCtx ctx{user, cb};
    EnumChildWindows(h, EnumChildRegisterProc, reinterpret_cast<LPARAM>(&ctx));
    return 0;
}

/// 단일 HWND 의 IDropTarget 등록 해제. g_dropTargets 에 보관된
/// owning reference 가 있으면 함께 Release 한다.
static void RevokeOnOne(HWND h) {
    auto it = g_dropTargets.find(h);
    if (it != g_dropTargets.end()) {
        RevokeDragDrop(h);
        it->second->Release();
        g_dropTargets.erase(it);
    }
}

namespace {
BOOL CALLBACK EnumChildRevokeProc(HWND child, LPARAM /*lp*/) {
    RevokeOnOne(child);
    return TRUE;
}
}  // namespace

/// HWND 및 그 모든 자손 HWND의 드롭 타겟을 해제한다.
/// `KSWV2_RegisterDropTarget`과 대칭 — 등록 시 자손 HWND에 추가한
/// owning reference 를 누수 없이 모두 회수한다.
extern "C" void KSWV2_RevokeDropTarget(void *hwnd) {
    if (!hwnd) return;
    HWND h = reinterpret_cast<HWND>(hwnd);
    RevokeOnOne(h);
    EnumChildWindows(h, EnumChildRevokeProc, 0);
}

/// 테스트 전용 — 등록 카운트 누수 회귀 단언용.
extern "C" int32_t KSWV2_DebugGetRegisteredCount(void) {
    return static_cast<int32_t>(g_dropTargets.size());
}
