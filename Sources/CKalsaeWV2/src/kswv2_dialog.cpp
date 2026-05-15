//
//  kswv2_dialog.cpp
//  CKalsaeWV2
//
//  모던 파일 다이얼로그 (IFileOpenDialog / IFileSaveDialog / IFileDialog).
//  레거시 GetOpenFileNameW / SHBrowseForFolderW를 대체한다.
//  호스트 HWND를 소유한 UI 스레드에서 호출해야 하며,
//  호출 스레드는 STA로 COM이 초기화되어 있어야 한다.
//

#include <wrl.h>
#include <shobjidl.h>
#include <shlwapi.h>
#include <string>
#include <vector>
#include "kswv2_internal.h"

using namespace Microsoft::WRL;

/// 파일 다이얼로그 필터를 COMDLG_FILTERSPEC 배열로 변환한다.
/// 반환된 배열은 호출자가 해제해야 한다 (각 문자열은 KSWV2_WcsDupCopy로 할당).
static COMDLG_FILTERSPEC *ConvertFilters(
    const KSWV2DialogFilter *filters,
    int32_t filter_count)
{
    if (!filters || filter_count <= 0) return nullptr;
    COMDLG_FILTERSPEC *specs = (COMDLG_FILTERSPEC *)malloc(
        filter_count * sizeof(COMDLG_FILTERSPEC));
    if (!specs) return nullptr;
    for (int32_t i = 0; i < filter_count; i++) {
        specs[i].pszName = KSWV2_WcsDupCopy(
            filters[i].name, wcslen(filters[i].name));
        specs[i].pszSpec = KSWV2_WcsDupCopy(
            filters[i].spec, wcslen(filters[i].spec));
    }
    return specs;
}

/// 변환된 필터 배열을 해제한다.
static void FreeFilters(COMDLG_FILTERSPEC *specs, int32_t count) {
    if (!specs) return;
    for (int32_t i = 0; i < count; i++) {
        KSWV2_Free((void *)specs[i].pszName);
        KSWV2_Free((void *)specs[i].pszSpec);
    }
    free(specs);
}

/// 파일 열기 다이얼로그를 표시한다. 다중 선택이 가능하다.
/// 반환된 경로 배열과 각 요소는 KSWV2_Free로 해제해야 한다.
extern "C" int32_t KSWV2_DialogOpenFile(
    void *hwnd,
    const wchar_t *title,
    const wchar_t *default_dir,
    const KSWV2DialogFilter *filters, int32_t filter_count,
    int32_t allow_multiple,
    wchar_t ***out_paths,
    int32_t *out_count)
{
    if (!hwnd || !out_paths || !out_count) return E_POINTER;

    *out_paths = nullptr;
    *out_count = 0;

    // IFileOpenDialog 생성
    ComPtr<IFileOpenDialog> dialog;
    HRESULT hr = CoCreateInstance(
        CLSID_FileOpenDialog,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&dialog));
    if (FAILED(hr)) return static_cast<int32_t>(hr);

    // 옵션 설정: 다중 선택, 파일 시스템 항목만, 경로 확인
    FILEOPENDIALOGOPTIONS opts = FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST;
    if (allow_multiple) opts |= FOS_ALLOWMULTISELECT;
    dialog->SetOptions(opts);

    // 제목 설정
    if (title) dialog->SetTitle(title);

    // 기본 폴더 설정
    if (default_dir) {
        ComPtr<IShellItem> folder;
        hr = SHCreateItemFromParsingName(
            default_dir, nullptr, IID_PPV_ARGS(&folder));
        if (SUCCEEDED(hr) && folder) {
            dialog->SetFolder(folder.Get());
        }
    }

    // 필터 설정
    COMDLG_FILTERSPEC *specs = ConvertFilters(filters, filter_count);
    if (specs) {
        dialog->SetFileTypes(filter_count, specs);
        if (filter_count > 0) dialog->SetFileTypeIndex(0);
    }

    // 다이얼로그 표시
    hr = dialog->Show(reinterpret_cast<HWND>(hwnd));
    if (FAILED(hr)) {
        FreeFilters(specs, filter_count);
        // 사용자 취소: S_OK + count=0
        return 0;
    }

    // 선택된 항목 가져오기
    ComPtr<IShellItemArray> items;
    hr = dialog->GetResults(&items);
    if (FAILED(hr) || !items) {
        FreeFilters(specs, filter_count);
        return static_cast<int32_t>(hr);
    }

    DWORD count = 0;
    items->GetCount(&count);
    if (count == 0) {
        FreeFilters(specs, filter_count);
        return 0;
    }

    // 경로 배열 할당
    wchar_t **paths = (wchar_t **)malloc(count * sizeof(wchar_t *));
    if (!paths) {
        FreeFilters(specs, filter_count);
        return E_OUTOFMEMORY;
    }

    for (DWORD i = 0; i < count; i++) {
        ComPtr<IShellItem> item;
        if (SUCCEEDED(items->GetItemAt(i, &item)) && item) {
            LPWSTR path = nullptr;
            if (SUCCEEDED(item->GetDisplayName(
                    SIGDN_FILESYSPATH, &path)) && path)
            {
                paths[i] = KSWV2_WcsDupCopy(path, wcslen(path));
                CoTaskMemFree(path);
            } else {
                paths[i] = nullptr;
            }
        } else {
            paths[i] = nullptr;
        }
    }

    FreeFilters(specs, filter_count);
    *out_paths = paths;
    *out_count = (int32_t)count;
    return 0;
}

/// 파일 저장 다이얼로그를 표시한다.
extern "C" int32_t KSWV2_DialogSaveFile(
    void *hwnd,
    const wchar_t *title,
    const wchar_t *default_dir,
    const wchar_t *default_name,
    const KSWV2DialogFilter *filters, int32_t filter_count,
    wchar_t **out_path,
    int32_t *out_chosen)
{
    if (!hwnd || !out_path || !out_chosen) return E_POINTER;

    *out_path = nullptr;
    *out_chosen = 0;

    // IFileSaveDialog 생성
    ComPtr<IFileSaveDialog> dialog;
    HRESULT hr = CoCreateInstance(
        CLSID_FileSaveDialog,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&dialog));
    if (FAILED(hr)) return static_cast<int32_t>(hr);

    // 옵션 설정
    FILEOPENDIALOGOPTIONS opts = FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST |
                                  FOS_OVERWRITEPROMPT;
    dialog->SetOptions(opts);

    // 제목 설정
    if (title) dialog->SetTitle(title);

    // 기본 파일명 설정
    if (default_name) dialog->SetFileName(default_name);

    // 기본 폴더 설정
    if (default_dir) {
        ComPtr<IShellItem> folder;
        hr = SHCreateItemFromParsingName(
            default_dir, nullptr, IID_PPV_ARGS(&folder));
        if (SUCCEEDED(hr) && folder) {
            dialog->SetFolder(folder.Get());
        }
    }

    // 필터 설정
    COMDLG_FILTERSPEC *specs = ConvertFilters(filters, filter_count);
    if (specs) {
        dialog->SetFileTypes(filter_count, specs);
        if (filter_count > 0) dialog->SetFileTypeIndex(0);
    }

    // 다이얼로그 표시
    hr = dialog->Show(reinterpret_cast<HWND>(hwnd));
    if (FAILED(hr)) {
        FreeFilters(specs, filter_count);
        return 0;  // 사용자 취소
    }

    // 선택된 파일 경로 가져오기
    ComPtr<IShellItem> result;
    hr = dialog->GetResult(&result);
    if (FAILED(hr) || !result) {
        FreeFilters(specs, filter_count);
        return static_cast<int32_t>(hr);
    }

    LPWSTR path = nullptr;
    hr = result->GetDisplayName(SIGDN_FILESYSPATH, &path);
    if (FAILED(hr) || !path) {
        FreeFilters(specs, filter_count);
        return static_cast<int32_t>(hr);
    }

    *out_path = KSWV2_WcsDupCopy(path, wcslen(path));
    CoTaskMemFree(path);
    *out_chosen = 1;

    FreeFilters(specs, filter_count);
    return 0;
}

/// 폴더 선택 다이얼로그를 표시한다 (IFileOpenDialog + FOS_PICKFOLDERS).
extern "C" int32_t KSWV2_DialogSelectFolder(
    void *hwnd,
    const wchar_t *title,
    const wchar_t *default_dir,
    wchar_t **out_path,
    int32_t *out_chosen)
{
    if (!hwnd || !out_path || !out_chosen) return E_POINTER;

    *out_path = nullptr;
    *out_chosen = 0;

    // IFileOpenDialog 생성 (폴더 선택 모드)
    ComPtr<IFileOpenDialog> dialog;
    HRESULT hr = CoCreateInstance(
        CLSID_FileOpenDialog,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&dialog));
    if (FAILED(hr)) return static_cast<int32_t>(hr);

    // 폴더 선택 모드로 설정
    FILEOPENDIALOGOPTIONS opts = FOS_FORCEFILESYSTEM |
                                  FOS_PATHMUSTEXIST |
                                  FOS_PICKFOLDERS;
    dialog->SetOptions(opts);

    // 제목 설정
    if (title) dialog->SetTitle(title);

    // 기본 폴더 설정
    if (default_dir) {
        ComPtr<IShellItem> folder;
        hr = SHCreateItemFromParsingName(
            default_dir, nullptr, IID_PPV_ARGS(&folder));
        if (SUCCEEDED(hr) && folder) {
            dialog->SetFolder(folder.Get());
        }
    }

    // 다이얼로그 표시
    hr = dialog->Show(reinterpret_cast<HWND>(hwnd));
    if (FAILED(hr)) return 0;  // 사용자 취소

    // 선택된 폴더 경로 가져오기
    ComPtr<IShellItem> result;
    hr = dialog->GetResult(&result);
    if (FAILED(hr) || !result) return static_cast<int32_t>(hr);

    LPWSTR path = nullptr;
    hr = result->GetDisplayName(SIGDN_FILESYSPATH, &path);
    if (FAILED(hr) || !path) return static_cast<int32_t>(hr);

    *out_path = KSWV2_WcsDupCopy(path, wcslen(path));
    CoTaskMemFree(path);
    *out_chosen = 1;

    return 0;
}
