//
//  kswv2.h
//  CKalsaeWV2
//
//  Microsoft WebView2 COM SDK 위의 C 전용 API 표면.
//  구현은 kswv2.cpp에 있다. Swift는 이 헤더만 들이고,
//  COM vtable·HRESULT·WRL 관련 코드는 전부 C++ 쪽에 남는다.
//
//  스레딩: 이곳의 모든 함수는 호스팅 HWND를 소유한 스레드(Win32 UI
//  스레드)에서 호출되어야 한다. 모든 콜백도 같은 스레드에서 발생한다.
//

#ifndef KSWV2_H
#define KSWV2_H

#include <stdint.h>
#include <wchar.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Opaque handles

typedef struct KSWV2EnvOpaque        *KSWV2Env;
typedef struct KSWV2ControllerOpaque *KSWV2Controller;
typedef struct KSWV2WebViewOpaque    *KSWV2WebView;

// MARK: - Callback signatures
//
// 모든 콜백은 등록 시 전달한 `user` 포인터를 다시 받는다.
// `hr`은 Win32 HRESULT(32비트 부호)이며, 콜백은 UI 스레드에서 발생한다.

typedef void (*KSWV2EnvCompletedCB)(
    void *user, int32_t hr, KSWV2Env env);

typedef void (*KSWV2ControllerCompletedCB)(
    void *user, int32_t hr, KSWV2Controller controller);

// `message_utf16`는 NUL 종료 UTF-16 JSON 문자열로, WebView2가 소유한다.
// 콜백 동안만 유효하므로 유지하려면 복사해야 한다.
typedef void (*KSWV2MessageCB)(
    void *user, const wchar_t *message_utf16);

typedef void (*KSWV2NavigationCompletedCB)(
    void *user, int32_t hr, int32_t is_success);

// MARK: - Environment

int32_t KSWV2_CreateEnvironment(
    const wchar_t *browser_executable_folder,   // NULL 가능
    const wchar_t *user_data_folder,            // NULL 가능
    void *user,
    KSWV2EnvCompletedCB completed);

void KSWV2_Env_Release(KSWV2Env env);

/// Wraps `GetAvailableCoreWebView2BrowserVersionString`. The caller owns
/// the returned `*version_out` and must release it with `CoTaskMemFree`.
/// `version_out` may be NULL when only the success/failure HRESULT is
/// needed. Returns 0 on success or a Win32 HRESULT on failure.
int32_t KSWV2_GetAvailableBrowserVersion(
    const wchar_t *browser_executable_folder,   // NULL 가능
    wchar_t **version_out);                     // NULL 가능

// MARK: - Controller / WebView

int32_t KSWV2_CreateController(
    KSWV2Env env,
    void *hwnd,                                 // 실제로는 HWND
    void *user,
    KSWV2ControllerCompletedCB completed);

void         KSWV2_Controller_Release(KSWV2Controller controller);
KSWV2WebView KSWV2_Controller_GetWebView(KSWV2Controller controller);
int32_t      KSWV2_Controller_SetBounds(
    KSWV2Controller controller, int32_t x, int32_t y, int32_t w, int32_t h);
int32_t      KSWV2_Controller_SetVisible(
    KSWV2Controller controller, int32_t visible);
int32_t      KSWV2_Controller_Close(KSWV2Controller controller);

// MARK: - WebView operations

int32_t KSWV2_Navigate(KSWV2WebView webview, const wchar_t *url);

/// Installs a single message handler. Subsequent calls replace the previous
/// handler. Returns S_OK (0) or an HRESULT on failure.
int32_t KSWV2_AddMessageHandler(
    KSWV2WebView webview, void *user, KSWV2MessageCB cb);

int32_t KSWV2_PostWebMessageAsJson(
    KSWV2WebView webview, const wchar_t *json_utf16);

int32_t KSWV2_ExecuteScript(
    KSWV2WebView webview, const wchar_t *script_utf16);

int32_t KSWV2_OpenDevTools(KSWV2WebView webview);

/// Disables or enables DevTools and default context menu. Called before the
/// first navigation to affect the initial document.
int32_t KSWV2_SetDevToolsEnabled(KSWV2WebView webview, int32_t enabled);

/// Toggles the WebView2 default (browser-style) context menu. Independent
/// from DevTools; setting `enabled = 0` only suppresses the menu and lets
/// the page render its own. Returns 0 on success.
int32_t KSWV2_SetDefaultContextMenusEnabled(KSWV2WebView webview, int32_t enabled);

/// Toggles the controller's `AllowExternalDrop` flag (Runtime 1.0.992+).
/// When `allow == 0` the webview rejects file drops from outside the
/// process, allowing the host's `IDropTarget` to receive them instead.
int32_t KSWV2_Controller_SetAllowExternalDrop(KSWV2Controller controller, int32_t allow);

// MARK: - 네이티브 파일 드래그 앤 드롭 (IDropTarget)
//
// `KSWV2_Controller_SetAllowExternalDrop(controller, 0)`과 호스트 HWND에
// `KSWV2_RegisterDropTarget`을 같이 쓰면 OS 파일 드롭이 WebView2
// 자식을 건너뛰고 호스트 측 이벤트로 올라온다. 이 쉬밌은 vtable을 C++에
// 숨긴 IDropTarget COM 객체를 감싸고, Swift 쪽에는 아래 C 콜백만 노출한다.
//
// 스레딩: 콜백은 UI 스레드에서 발생한다(OLE 드롭 매니저가 일반 메시지
// 큐를 통해 디스패치). `paths`와 내부 문자열의 수명은 콜백 동안만 유효하다.

/// Drop event kinds reported by `KSWV2DropCB`.
typedef enum {
    KSWV2_DropEvent_Enter = 0,   // 드롭 가능한 데이터가 HWND에 진입
    KSWV2_DropEvent_Leave = 1,   // 드래그 취소 또는 이탈
    KSWV2_DropEvent_Drop  = 2,   // 사용자가 놓음 — paths는 드롭 내용을 내제
} KSWV2DropEventKind;

/// Drop callback. `paths` is an array of `paths_count` UTF-16 strings.
/// On `KSWV2_DropEvent_Leave` the array is NULL and the count is zero.
/// `screen_x` / `screen_y` are screen coordinates (POINTL).
///
/// Return 0 to ACCEPT (DROPEFFECT_COPY), non-zero to REJECT
/// (DROPEFFECT_NONE). The accept/reject decision made on `Enter` is
/// remembered for subsequent `DragOver` ticks.
typedef int32_t (*KSWV2DropCB)(
    void *user,
    int32_t event_kind,
    int32_t screen_x,
    int32_t screen_y,
    const wchar_t **paths,
    int32_t paths_count);

/// Calls `OleInitialize` for the calling thread (idempotent). Required
/// before `RegisterDragDrop`. Returns 0 on S_OK / S_FALSE, otherwise the
/// HRESULT from `OleInitialize`.
int32_t KSWV2_OleInitializeOnce(void);

/// Installs an `IDropTarget` on `hwnd`. Replaces any drop target
/// previously installed via this function. Returns 0 (S_OK) on success.
int32_t KSWV2_RegisterDropTarget(
    void *hwnd, void *user, KSWV2DropCB cb);

/// Revokes the drop target on `hwnd`. Safe to call on an HWND with no
/// registered target.
void KSWV2_RevokeDropTarget(void *hwnd);

int32_t KSWV2_AddScriptToExecuteOnDocumentCreated(
    KSWV2WebView webview, const wchar_t *script_utf16);

int32_t KSWV2_AddNavigationCompletedHandler(
    KSWV2WebView webview, void *user, KSWV2NavigationCompletedCB cb);

// MARK: - 가상 호스트 매핑 (https 가상 호스트를 통한 kb:// 대체)
//
// 프론트엔드를 실제 웹 오리진에 네트워크 없이 제공할 수 있도록 https
// 가상 호스트(예: `app.kalsae`)를 로컬 폴더에 매핑한다.
// ICoreWebView2_3 (런타임 1.0.864+) 필요.
//
// `access_kind`:
//   0 = DENY            (해당 오리진으로의 CORS 접근 차단)
//   1 = ALLOW           (동일 오리진에서만 접근 허용)
//   2 = DENY_CORS       (내비게이션은 허용, 교차 오리진 요청은 차단)
int32_t KSWV2_SetVirtualHostNameToFolderMapping(
    KSWV2WebView webview,
    const wchar_t *host_name,
    const wchar_t *folder_path,
    int32_t access_kind);

// MARK: - 웹 리소스 요청 가로채기
//
// 설치된 URI 필터(`KSWV2_AddWebResourceRequestedFilter` 참조)에 일치하는
// 요청에 대해 임의의 HTTP 응답을 제공하는 동기 핸들러를 등록한다.
// 핸들러는 UI 스레드에서 실행되며, WebView2는 콜백 반환 전까지 요청을
// 차단한다.
//
// 반환값: 0이면 합성한 응답을 제공; 0이 아니면 제공 거절(WebView2가
// 기본 구현을 계속 수행).
//
// 성공(`return 0`) 시 소유권:
//   *out_data          — *out_len 바이트 크기의 malloc된 버퍼.
//   *out_content_type  — _wcsdup되었거나 NULL. `Content-Type`으로 사용.
//   *out_csp           — _wcsdup되었거나 NULL. `Content-Security-Policy`로 사용.
// 쉬밌이 소유권을 가져가 응답을 조립한 뒤 free()로 해제한다.
typedef int32_t (*KSWV2ResourceCB)(
    void *user,
    const wchar_t *uri,
    uint8_t **out_data,
    size_t *out_len,
    wchar_t **out_content_type,
    wchar_t **out_csp);

int32_t KSWV2_AddWebResourceRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2ResourceCB cb);

/// Adds a URI wildcard pattern (e.g. `"https://app.kalsae/*"`) to the
/// filter list for the installed resource-requested handler. Multiple
/// filters OR together. Must be called after
/// `KSWV2_AddWebResourceRequestedHandler`.
int32_t KSWV2_AddWebResourceRequestedFilter(
    KSWV2WebView webview, const wchar_t *uri_wildcard);

// MARK: - 메모리 할당 헬퍼
//
// Swift가 반환하는 응답 버퍼는 C++ 쪽에서 `free()`할 수 있어야 한다.
// Swift의 자체 할당자가 CRT 할당자와 일치한다는 보장이 없으므로, 콜백이
// 이 헬퍼를 통해 할당한다. 이는 쉬밌이 링크한 같은 CRT의 `malloc` /
// `_wcsdup`을 그대로 감싼 것이다.

void    *KSWV2_Alloc(size_t n);
void     KSWV2_Free(void *p);
wchar_t *KSWV2_WcsDupCopy(const wchar_t *src, size_t len);

// MARK: - WinRT toast notifications

/// Sets the calling process's AppUserModelID. Required for toast
/// notifications to associate with the application's Start Menu
/// shortcut. Returns 0 (S_OK) on success.
int32_t KSWV2_SetAppUserModelID(const wchar_t *aumid);

/// Posts a Windows.UI.Notifications XAML toast under `aumid`. `title`
/// and `body` are optional (NULL or empty string suppresses the
/// corresponding `<text>` element). Returns 0 on success or a Win32
/// HRESULT on failure (e.g. RPC_E_DISCONNECTED if the AUMID is not
/// registered with a Start Menu shortcut).
int32_t KSWV2_ShowToast(
    const wchar_t *aumid,
    const wchar_t *title,
    const wchar_t *body);

#ifdef __cplusplus
}
#endif

#endif // KSWV2_H
