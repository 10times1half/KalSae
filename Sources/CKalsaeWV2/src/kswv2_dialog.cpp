//
//  kswv2_dialog.cpp
//  CKalsaeWV2
//
//  Modern Windows Vista+ common item dialogs (IFileOpenDialog /
//  IFileSaveDialog). Replaces the legacy GetOpenFileNameW /
//  GetSaveFileNameW / SHBrowseForFolderW used historically by
//  KSWindowsDialogBackend.
//
//  스레딩: 호스트 HWND를 소유한 UI 스레드에서 호출되어야 한다.
//  COM은 STA로 초기화되어 있어야 하며, KSWV2_OleInitializeOnce() 또는
//  CoInitialize(NULL) 등으로 확보한다.
//

#include <objbase.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <stdint.h>
#include <wchar.h>
#include "kswv2.h"

namespace {

inline IShellItem *MakeShellItemFromPath(const wchar_t *path) {
    if (!path || !*path) return nullptr;
    IShellItem *item = nullptr;
    HRESULT hr = SHCreateItemFromParsingName(path, nullptr, IID_PPV_ARGS(&item));
    return SUCCEEDED(hr) ? item : nullptr;
}

inline wchar_t *DupShellItemDisplayName(IShellItem *item) {
    if (!item) return nullptr;
    LPWSTR raw = nullptr;
    if (FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &raw)) || !raw) {
        return nullptr;
    }
    size_t len = wcslen(raw);
    wchar_t *out = KSWV2_WcsDupCopy(raw, len);
    CoTaskMemFree(raw);
    return out;
}

inline HRESULT ApplyCommonOptions(
    IFileDialog *dlg,
    const wchar_t *title,
    const wchar_t *default_dir,
    const KSWV2DialogFilter *filters, int32_t filter_count)
{
    if (title && *title) {
        dlg->SetTitle(title);
    }
    if (default_dir && *default_dir) {
        IShellItem *folder = MakeShellItemFromPath(default_dir);
        if (folder) {
            dlg->SetDefaultFolder(folder);
            folder->Release();
        }
    }
    if (filters && filter_count > 0) {
        // COMDLG_FILTERSPEC는 IFileDialog 호출이 끝나기 전까지 살아 있어야
        // 한다. 호출자 스택에 그대로 둔다.
        COMDLG_FILTERSPEC *specs =
            (COMDLG_FILTERSPEC *)KSWV2_Alloc(sizeof(COMDLG_FILTERSPEC) * (size_t)filter_count);
        if (!specs) return E_OUTOFMEMORY;
        for (int32_t i = 0; i < filter_count; ++i) {
            specs[i].pszName = filters[i].name ? filters[i].name : L"";
            specs[i].pszSpec = filters[i].spec ? filters[i].spec : L"*.*";
        }
        HRESULT hr = dlg->SetFileTypes((UINT)filter_count, specs);
        KSWV2_Free(specs);
        if (FAILED(hr)) return hr;
        dlg->SetFileTypeIndex(1);
    }
    return S_OK;
}

inline HRESULT CollectPath(IShellItem *item, wchar_t **out) {
    if (!item || !out) return E_POINTER;
    *out = DupShellItemDisplayName(item);
    return *out ? S_OK : E_FAIL;
}

} // namespace

extern "C" int32_t KSWV2_DialogOpenFile(
    void *hwnd,
    const wchar_t *title,
    const wchar_t *default_dir,
    const KSWV2DialogFilter *filters, int32_t filter_count,
    int32_t allow_multiple,
    wchar_t ***out_paths,
    int32_t *out_count)
{
    if (!out_paths || !out_count) return E_POINTER;
    *out_paths = nullptr;
    *out_count = 0;

    IFileOpenDialog *dlg = nullptr;
    HRESULT hr = CoCreateInstance(
        CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&dlg));
    if (FAILED(hr)) return hr;

    DWORD opts = 0;
    dlg->GetOptions(&opts);
    opts |= FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_FILEMUSTEXIST;
    if (allow_multiple) opts |= FOS_ALLOWMULTISELECT;
    dlg->SetOptions(opts);

    hr = ApplyCommonOptions(dlg, title, default_dir, filters, filter_count);
    if (FAILED(hr)) { dlg->Release(); return hr; }

    hr = dlg->Show((HWND)hwnd);
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
        dlg->Release();
        return S_OK;     // 사용자가 취소함
    }
    if (FAILED(hr)) { dlg->Release(); return hr; }

    IShellItemArray *items = nullptr;
    hr = dlg->GetResults(&items);
    dlg->Release();
    if (FAILED(hr) || !items) return FAILED(hr) ? hr : E_FAIL;

    DWORD count = 0;
    hr = items->GetCount(&count);
    if (FAILED(hr) || count == 0) {
        items->Release();
        return FAILED(hr) ? hr : S_OK;
    }

    wchar_t **paths = (wchar_t **)KSWV2_Alloc(sizeof(wchar_t *) * (size_t)count);
    if (!paths) {
        items->Release();
        return E_OUTOFMEMORY;
    }
    int32_t written = 0;
    for (DWORD i = 0; i < count; ++i) {
        IShellItem *one = nullptr;
        if (FAILED(items->GetItemAt(i, &one)) || !one) continue;
        wchar_t *p = nullptr;
        if (SUCCEEDED(CollectPath(one, &p)) && p) {
            paths[written++] = p;
        }
        one->Release();
    }
    items->Release();

    if (written == 0) {
        KSWV2_Free(paths);
        return S_OK;
    }
    *out_paths = paths;
    *out_count = written;
    return S_OK;
}

extern "C" int32_t KSWV2_DialogSaveFile(
    void *hwnd,
    const wchar_t *title,
    const wchar_t *default_dir,
    const wchar_t *default_name,
    const KSWV2DialogFilter *filters, int32_t filter_count,
    wchar_t **out_path,
    int32_t *out_chosen)
{
    if (!out_path || !out_chosen) return E_POINTER;
    *out_path = nullptr;
    *out_chosen = 0;

    IFileSaveDialog *dlg = nullptr;
    HRESULT hr = CoCreateInstance(
        CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&dlg));
    if (FAILED(hr)) return hr;

    DWORD opts = 0;
    dlg->GetOptions(&opts);
    opts |= FOS_FORCEFILESYSTEM | FOS_OVERWRITEPROMPT | FOS_PATHMUSTEXIST;
    dlg->SetOptions(opts);

    hr = ApplyCommonOptions(dlg, title, default_dir, filters, filter_count);
    if (FAILED(hr)) { dlg->Release(); return hr; }

    if (default_name && *default_name) {
        dlg->SetFileName(default_name);
    }

    hr = dlg->Show((HWND)hwnd);
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
        dlg->Release();
        return S_OK;
    }
    if (FAILED(hr)) { dlg->Release(); return hr; }

    IShellItem *item = nullptr;
    hr = dlg->GetResult(&item);
    dlg->Release();
    if (FAILED(hr) || !item) return FAILED(hr) ? hr : E_FAIL;

    wchar_t *p = nullptr;
    hr = CollectPath(item, &p);
    item->Release();
    if (FAILED(hr) || !p) return FAILED(hr) ? hr : E_FAIL;

    *out_path = p;
    *out_chosen = 1;
    return S_OK;
}

extern "C" int32_t KSWV2_DialogSelectFolder(
    void *hwnd,
    const wchar_t *title,
    const wchar_t *default_dir,
    wchar_t **out_path,
    int32_t *out_chosen)
{
    if (!out_path || !out_chosen) return E_POINTER;
    *out_path = nullptr;
    *out_chosen = 0;

    IFileOpenDialog *dlg = nullptr;
    HRESULT hr = CoCreateInstance(
        CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&dlg));
    if (FAILED(hr)) return hr;

    DWORD opts = 0;
    dlg->GetOptions(&opts);
    opts |= FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST;
    dlg->SetOptions(opts);

    if (title && *title) {
        dlg->SetTitle(title);
    }
    if (default_dir && *default_dir) {
        IShellItem *folder = MakeShellItemFromPath(default_dir);
        if (folder) {
            dlg->SetDefaultFolder(folder);
            folder->Release();
        }
    }

    hr = dlg->Show((HWND)hwnd);
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
        dlg->Release();
        return S_OK;
    }
    if (FAILED(hr)) { dlg->Release(); return hr; }

    IShellItem *item = nullptr;
    hr = dlg->GetResult(&item);
    dlg->Release();
    if (FAILED(hr) || !item) return FAILED(hr) ? hr : E_FAIL;

    wchar_t *p = nullptr;
    hr = CollectPath(item, &p);
    item->Release();
    if (FAILED(hr) || !p) return FAILED(hr) ? hr : E_FAIL;

    *out_path = p;
    *out_chosen = 1;
    return S_OK;
}
