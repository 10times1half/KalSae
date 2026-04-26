//
//  kswv2_drop.cpp
//  CKalsaeWV2
//
//  Native `IDropTarget` COM class wrapping CF_HDROP file drops, plus
//  the `KSWV2_OleInitializeOnce` / `KSWV2_RegisterDropTarget` /
//  `KSWV2_RevokeDropTarget` C entry points.
//

#include <ole2.h>
#include <shellapi.h>
#include <new>
#include <vector>
#include <string>
#include "kswv2_internal.h"

namespace {

bool ExtractCFHDROPPaths(IDataObject *data, std::vector<std::wstring> &out) {
    if (!data) return false;
    FORMATETC fmt{};
    fmt.cfFormat = CF_HDROP;
    fmt.ptd = nullptr;
    fmt.dwAspect = DVASPECT_CONTENT;
    fmt.lindex = -1;
    fmt.tymed = TYMED_HGLOBAL;

    STGMEDIUM med{};
    HRESULT hr = data->GetData(&fmt, &med);
    if (FAILED(hr)) return false;

    bool ok = false;
    HDROP hDrop = (HDROP)GlobalLock(med.hGlobal);
    if (hDrop) {
        UINT count = DragQueryFileW(hDrop, 0xFFFFFFFF, nullptr, 0);
        out.reserve(count);
        for (UINT i = 0; i < count; ++i) {
            UINT need = DragQueryFileW(hDrop, i, nullptr, 0);
            std::wstring buf;
            buf.resize(need);
            if (need > 0) {
                DragQueryFileW(hDrop, i, &buf[0], need + 1);
            }
            out.emplace_back(std::move(buf));
        }
        GlobalUnlock(med.hGlobal);
        ok = true;
    }
    ReleaseStgMedium(&med);
    return ok;
}

class KSDropTarget : public IDropTarget {
public:
    KSDropTarget(void *user, KSWV2DropCB cb)
        : m_ref(1), m_user(user), m_cb(cb), m_accepted(false) {}

    ULONG STDMETHODCALLTYPE AddRef() override {
        return (ULONG)InterlockedIncrement(&m_ref);
    }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG r = InterlockedDecrement(&m_ref);
        if (r == 0) delete this;
        return (ULONG)r;
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IDropTarget) {
            *ppv = static_cast<IDropTarget *>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }

    HRESULT STDMETHODCALLTYPE DragEnter(
        IDataObject *pDataObj, DWORD,
        POINTL pt, DWORD *pdwEffect) override
    {
        std::vector<std::wstring> paths;
        ExtractCFHDROPPaths(pDataObj, paths);
        int32_t rc = Dispatch(KSWV2_DropEvent_Enter, pt, paths);
        m_accepted = (rc == 0) && !paths.empty();
        if (pdwEffect) *pdwEffect = m_accepted ? DROPEFFECT_COPY : DROPEFFECT_NONE;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE DragOver(
        DWORD, POINTL, DWORD *pdwEffect) override
    {
        if (pdwEffect) *pdwEffect = m_accepted ? DROPEFFECT_COPY : DROPEFFECT_NONE;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE DragLeave() override {
        std::vector<std::wstring> empty;
        POINTL pt{0, 0};
        Dispatch(KSWV2_DropEvent_Leave, pt, empty);
        m_accepted = false;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE Drop(
        IDataObject *pDataObj, DWORD,
        POINTL pt, DWORD *pdwEffect) override
    {
        std::vector<std::wstring> paths;
        ExtractCFHDROPPaths(pDataObj, paths);
        int32_t rc = Dispatch(KSWV2_DropEvent_Drop, pt, paths);
        bool accept = (rc == 0) && !paths.empty();
        if (pdwEffect) *pdwEffect = accept ? DROPEFFECT_COPY : DROPEFFECT_NONE;
        m_accepted = false;
        return S_OK;
    }

private:
    int32_t Dispatch(int32_t kind, POINTL pt, const std::vector<std::wstring> &paths) {
        if (!m_cb) return 1;
        std::vector<const wchar_t *> raw;
        raw.reserve(paths.size());
        for (const auto &s : paths) raw.push_back(s.c_str());
        return m_cb(m_user, kind, (int32_t)pt.x, (int32_t)pt.y,
                    raw.empty() ? nullptr : raw.data(),
                    (int32_t)raw.size());
    }

    LONG m_ref;
    void *m_user;
    KSWV2DropCB m_cb;
    bool m_accepted;
};

} // namespace

extern "C" int32_t KSWV2_OleInitializeOnce(void) {
    HRESULT hr = OleInitialize(nullptr);
    if (hr == S_OK || hr == S_FALSE || hr == RPC_E_CHANGED_MODE) return 0;
    return (int32_t)hr;
}

extern "C" int32_t KSWV2_RegisterDropTarget(
    void *hwnd, void *user, KSWV2DropCB cb)
{
    if (!hwnd || !cb) return E_INVALIDARG;
    HWND h = (HWND)hwnd;
    RevokeDragDrop(h);
    KSDropTarget *t = new (std::nothrow) KSDropTarget(user, cb);
    if (!t) return E_OUTOFMEMORY;
    HRESULT hr = RegisterDragDrop(h, t);
    t->Release();
    return (int32_t)hr;
}

extern "C" void KSWV2_RevokeDropTarget(void *hwnd) {
    if (!hwnd) return;
    RevokeDragDrop((HWND)hwnd);
}
