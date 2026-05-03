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

/// `GetAvailableCoreWebView2BrowserVersionString`를 래픡한다.
/// 반환된 `*version_out`은 호출자가 소유하며 `CoTaskMemFree`로
/// 해제해야 한다. 성공/실패 HRESULT만 필요할 때는
/// `version_out`을 NULL로 줌수 있다. 성공 시 0, 실패 시 Win32 HRESULT.
int32_t KSWV2_GetAvailableBrowserVersion(
    const wchar_t *browser_executable_folder,   // NULL 가능
    wchar_t **version_out);                     // NULL 가능

// MARK: - 컨트롤러 / WebView

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

// MARK: - WebView 작업

int32_t KSWV2_Navigate(KSWV2WebView webview, const wchar_t *url);

/// 단일 메시지 핸들러를 설치한다. 이후 호출은 이전 핸들러를 대체한다.
/// S_OK(0) 또는 실패 시 HRESULT를 반환한다.
int32_t KSWV2_AddMessageHandler(
    KSWV2WebView webview, void *user, KSWV2MessageCB cb);

int32_t KSWV2_PostWebMessageAsJson(
    KSWV2WebView webview, const wchar_t *json_utf16);

int32_t KSWV2_ExecuteScript(
    KSWV2WebView webview, const wchar_t *script_utf16);

int32_t KSWV2_OpenDevTools(KSWV2WebView webview);

/// DevTools와 기본 컨텍스트 메뉴를 비활성화하거나 활성화한다.
/// 첫 번째 탐색 전에 호출해야 초기 문서에 적용된다.
int32_t KSWV2_SetDevToolsEnabled(KSWV2WebView webview, int32_t enabled);

/// WebView2 기본 (브라우저 스타일) 컨텍스트 메뉴를 토글한다.
/// DevTools와 독립적; `enabled = 0`은 메뉴만 억제하고 페이지가
/// 자체 메뉴를 렌더링할 수 있도록 한다. 성공 시 0을 반환한다.
int32_t KSWV2_SetDefaultContextMenusEnabled(KSWV2WebView webview, int32_t enabled);

/// 컨트롤러의 `AllowExternalDrop` 플래그를 토글한다 (Runtime 1.0.992+).
/// `allow == 0`이면 웹뷰는 프로세스 외부 파일 드롭을 거부하고
/// 호스트의 `IDropTarget`이 대신 수신할 수 있게 한다.
int32_t KSWV2_Controller_SetAllowExternalDrop(KSWV2Controller controller, int32_t allow);

// MARK: - 비주얼 / 런타임 튜닝 (Phase C2)
//
// 모두 controller / settings가 이미 생성된 다음에 호출해야 한다.
// 일치하는 인터페이스(`ICoreWebView2Controller2`,
// `ICoreWebView2Settings5`)를 지원하지 않는 런타임 버전에서는
// `E_NOINTERFACE`를 그대로 돌려준다 — 호출자는 무시할 수 있다.

/// 컨트롤러의 기본 배경 색을 설정한다. ARGB 바이트 순서:
/// `a`는 알파 쳬널, `r/g/b`는 색상 쳬널 (각 0..255).
/// `a = 0` + `KSWindowConfig.transparent` 윈도우를 조합하면
/// WebView 자체를 투명하게 만들 수 있다. `ICoreWebView2Controller2`이 필요하다.
int32_t KSWV2_Controller_SetDefaultBackgroundColor(
    KSWV2Controller controller,
    uint8_t a, uint8_t r, uint8_t g, uint8_t b);

/// 컨트롤러 레벨 즐 배율을 설정한다. `1.0`은 원본; 허용
/// 범위는 WebView2 SDK를 따른다 (≈ 0.25..5.0).
int32_t KSWV2_Controller_SetZoomFactor(
    KSWV2Controller controller, double factor);

/// 현재 컨트롤러 술 배율을 읽는다. 성공 시 0을 반환하고
/// 배율을 `*out_factor`에 쓴다. 두 인수 중 하나라도 NULL이면
/// `E_POINTER`를 반환한다.
int32_t KSWV2_Controller_GetZoomFactor(
    KSWV2Controller controller, double *out_factor);

/// WebView2 설정에서 `IsPinchZoomEnabled`를 토글한다.
/// `ICoreWebView2Settings5`가 필요하다. 성공 시 0, 이전 런타임에서는 `E_NOINTERFACE`.
int32_t KSWV2_SetPinchZoomEnabled(KSWV2WebView webview, int32_t enabled);

// MARK: - 인쇄 (Phase D1)
//
// `kind`: 0 = browser-style print preview (COREWEBVIEW2_PRINT_DIALOG_KIND_BROWSER),
//         1 = OS system print dialog (COREWEBVIEW2_PRINT_DIALOG_KIND_SYSTEM).
// 동기 호출. 반환값은 HRESULT. 런타임이 ICoreWebView2_16를 지원하지
// 않으면 E_NOINTERFACE를 돌려준다.
int32_t KSWV2_ShowPrintUI(KSWV2WebView webview, int32_t kind);

// MARK: - 캐펠첫 프리븷 (Phase D3)
//
// `format`: 0 = PNG, 1 = JPEG.
// 콜백은 UI 스레드에서 1회 발생한다. `data`/`len`은 콜백 동안만 유효하며
// Swift 측은 즉시 복사해야 한다. 호출 자체가 실패하면(`E_POINTER` 등)
// 콜백은 호출되지 않으므로 수신측에서 retain한 박스를 직접 해제해야 한다.
typedef void (*KSWV2CaptureCB)(
    void *user, int32_t hr,
    const uint8_t *data, size_t len);

int32_t KSWV2_CapturePreview(
    KSWV2WebView webview, int32_t format,
    void *user, KSWV2CaptureCB cb);

// MARK: - 네이티브 파일 드래그 앤 드롭 (IDropTarget)
//
// `KSWV2_Controller_SetAllowExternalDrop(controller, 0)`과 호스트 HWND에
// `KSWV2_RegisterDropTarget`을 같이 쓰면 OS 파일 드롭이 WebView2
// 자식을 건너뛰고 호스트 측 이벤트로 올라온다. 이 쉬밌은 vtable을 C++에
// 숨긴 IDropTarget COM 객체를 감싸고, Swift 쪽에는 아래 C 콜백만 노출한다.
//
// 스레딩: 콜백은 UI 스레드에서 발생한다(OLE 드롭 매니저가 일반 메시지
// 큐를 통해 디스패치). `paths`와 내부 문자열의 수명은 콜백 동안만 유효하다.

/// `KSWV2DropCB`가 보고하는 드롭 이벤트 종류.
typedef enum {
    KSWV2_DropEvent_Enter = 0,   // 드롭 가능한 데이터가 HWND에 진입
    KSWV2_DropEvent_Leave = 1,   // 드래그 취소 또는 이탈
    KSWV2_DropEvent_Drop  = 2,   // 사용자가 놓음 — paths는 드롭 내용을 내제
} KSWV2DropEventKind;

/// 드롭 콜백. `paths`는 `paths_count` 개의 UTF-16 문자열 배열이다.
/// `KSWV2_DropEvent_Leave`시 배열은 NULL이고 개수는 0이다.
/// `screen_x` / `screen_y`는 화면 좌표(POINTL)이다.
///
/// 0을 반환하면 수락 (DROPEFFECT_COPY), 비제로이면 거부
/// (DROPEFFECT_NONE)다. `Enter`에서 내린 수락/거부 결정은
/// 이후 `DragOver` 틱에도 유지된다.
typedef int32_t (*KSWV2DropCB)(
    void *user,
    int32_t event_kind,
    int32_t screen_x,
    int32_t screen_y,
    const wchar_t **paths,
    int32_t paths_count);

/// 호출 스레드에 `OleInitialize`를 호출한다 (멱등성). `RegisterDragDrop` 전에
/// 필요하다. S_OK / S_FALSE 시 0, 그 외에는 `OleInitialize`의 HRESULT.
int32_t KSWV2_OleInitializeOnce(void);

/// `hwnd`에 `IDropTarget`을 설치한다. 이전에 이 함수로 설치된
/// 드롭 타겟을 대체한다. 성공 시 0 (S_OK)을 반환한다.
int32_t KSWV2_RegisterDropTarget(
    void *hwnd, void *user, KSWV2DropCB cb);

/// `hwnd`의 드롭 타겟을 해제한다. 등록된 타겟이 없는 HWND에도 안전하게 호출할 수 있다.
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

/// 이 webview의 자산 응답에 Cross-Origin Isolation 헤더(COOP/COEP/CORP)를
/// 자동 추가할지 토글한다. `enabled != 0`이면 다음 3개 헤더가
/// 모든 WebResourceRequested 응답에 붙는다:
///   Cross-Origin-Opener-Policy: same-origin
///   Cross-Origin-Embedder-Policy: require-corp
///   Cross-Origin-Resource-Policy: same-origin
/// 0이면 비활성화. 항상 0(S_OK)을 반환한다.
/// `KSWV2_AddWebResourceRequestedHandler`보다 먼저 또는 나중에 호출 가능.
int32_t KSWV2_SetCrossOriginIsolation(
    KSWV2WebView webview, int32_t enabled);

// MARK: - 보안 핸들러

// 새 창(팝업) 요청 핸들러.
// `window.open()` / `target="_blank"` 등으로 WebView2가 새 창을
// 열려할 때 호출된다.
// 콜백 반환값: 0 = 요청 거부 (Handled=TRUE, NewWindow=null),
//              그 외 = 허용(호스트가 직접 NewWindow 처리 필요).
// uri_utf16: 요청된 목적지 URL (항상 non-null).
typedef int32_t (*KSWV2NewWindowCB)(void *user, const wchar_t *uri_utf16);

int32_t KSWV2_AddNewWindowRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2NewWindowCB cb);

// 권한 요청 핸들러.
// 마이크, 카메라, 지오로케이션 등 민감한 API 요청 시 호출된다.
// kind는 COREWEBVIEW2_PERMISSION_KIND 정수값.
// 콜백 반환값: 0 = DENY, 1 = ALLOW, 2 = DEFAULT (WebView2 기본 처리).
typedef int32_t (*KSWV2PermissionCB)(
    void *user, const wchar_t *uri_utf16, int32_t kind);

int32_t KSWV2_AddPermissionRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2PermissionCB cb);

// 다운로드 시작 핸들러 (ICoreWebView2_4).
// 페이지가 파일 다운로드를 시작할 때 호출된다.
// url_utf16:  다운로드 URL.
// mime_utf16: MIME 타입 (없으면 빈 문자열).
// 콜백 반환값: 0 = 다운로드 허용, 1 = 취소.
typedef int32_t (*KSWV2DownloadStartingCB)(
    void *user, const wchar_t *url_utf16, const wchar_t *mime_utf16);

int32_t KSWV2_AddDownloadStartingHandler(
    KSWV2WebView webview, void *user, KSWV2DownloadStartingCB cb);

// TLS/서버 인증서 오류 핸들러 (ICoreWebView2_14).
// 콜백 반환값: 0 = 탐색 취소(deny-secure 기본값), 1 = 계속(허용).
// 지원하지 않는 런타임에서 KSWV2_AddServerCertificateErrorHandler는
// E_NOINTERFACE를 반환하며 핸들러가 설치되지 않는다.
typedef int32_t (*KSWV2ServerCertErrorCB)(void *user);

int32_t KSWV2_AddServerCertificateErrorHandler(
    KSWV2WebView webview, void *user, KSWV2ServerCertErrorCB cb);

// HTTP Basic/Digest 인증 요청 핸들러 (ICoreWebView2_10).
// 콜백 반환값: 0 = 취소(자격증명 없이 거부), 1 = 계속(기본 처리).
// 기본 정책: 취소(0). 지원하지 않는 런타임에서 E_NOINTERFACE.
typedef int32_t (*KSWV2BasicAuthCB)(
    void *user, const wchar_t *uri_utf16, const wchar_t *challenge_utf16);

int32_t KSWV2_AddBasicAuthenticationHandler(
    KSWV2WebView webview, void *user, KSWV2BasicAuthCB cb);

// 클라이언트 인증서 요청 핸들러 (ICoreWebView2_5).
// 콜백 반환값: 0 = 취소(인증서 없이 진행), 1 = 기본 처리(OS 선택기).
// 기본 정책: 취소(0). 지원하지 않는 런타임에서 E_NOINTERFACE.
typedef int32_t (*KSWV2ClientCertCB)(void *user, const wchar_t *host_utf16);

int32_t KSWV2_AddClientCertificateHandler(
    KSWV2WebView webview, void *user, KSWV2ClientCertCB cb);


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
/// corresponding `<text>` element). `tag` is used as the WinRT toast tag
/// so the notification can be retracted with `KSWV2_CancelToast`. Pass
/// NULL or empty string to post without a tag. Returns 0 on success or a
/// Win32 HRESULT on failure (e.g. RPC_E_DISCONNECTED if the AUMID is not
/// registered with a Start Menu shortcut).
int32_t KSWV2_ShowToast(
    const wchar_t *aumid,
    const wchar_t *title,
    const wchar_t *body,
    const wchar_t *tag);

/// Removes the toast notification identified by `tag` from the Action
/// Center history of `aumid`. Uses `IToastNotificationHistory::
/// RemoveGroupedTagWithId` with an empty group. Returns S_OK (0) when the
/// removal succeeds or when no matching notification is found. A non-zero
/// return indicates a WinRT activation failure.
int32_t KSWV2_CancelToast(
    const wchar_t *aumid,
    const wchar_t *tag);

// MARK: - 이미지(WIC) — PNG ↔ DIB 변환
//
// 클립보드 이미지 입출력에 쓰인다. Windows의 클립보드는 PNG가 아닌
// `CF_DIB`/`CF_DIBV5` 비트맵을 표준으로 다루므로 PNG↔DIB 변환을
// 거쳐야 한다.
//
// 둘 다 성공 시 0을 반환하고 `out_data`/`out_size`에 새로 할당된
// 버퍼를 기록한다. 호출자는 `KSWV2_Free`로 해제해야 한다. 실패 시
// HRESULT(또는 음수 errno)를 반환하며 출력 인자는 건드리지 않는다.
//
// `dib_bytes`는 `BITMAPINFOHEADER`(또는 `BITMAPV5HEADER`)부터 시작하는
// 보통 `CF_DIB` 페이로드다 — `BITMAPFILEHEADER`는 포함되지 않는다.
// 출력 DIB는 32-bpp BGRA, bottom-up이다.

int32_t KSImage_PNGToDIB(
    const uint8_t *png_bytes, size_t png_size,
    uint8_t **out_data, size_t *out_size);

int32_t KSImage_DIBToPNG(
    const uint8_t *dib_bytes, size_t dib_size,
    uint8_t **out_data, size_t *out_size);

// MARK: - 모던 파일 다이얼로그 (IFileOpenDialog / IFileSaveDialog)
//
// 레거시 GetOpenFileNameW / SHBrowseForFolderW를 대체. 호스트 HWND를
// 소유한 UI 스레드에서 호출해야 하며, 호출 스레드는 STA로 COM이
// 초기화되어 있어야 한다. 모든 입력 문자열은 NULL 가능(있는 경우만 적용).
//
// 반환값은 HRESULT(0=S_OK). 사용자가 취소하면 S_OK + `*out_count == 0`
// 또는 `*out_chosen == 0`이 돌아온다.
//
// 출력 문자열은 KSWV2_WcsDupCopy로 할당되었으므로 호출자는 KSWV2_Free로
// 각 문자열을 해제해야 하며, OpenFile의 배열도 KSWV2_Free로 해제한다.

typedef struct {
    const wchar_t *name;     // 표시 이름 (예: L"이미지")
    const wchar_t *spec;     // 패턴 — 세미콜론 구분 (예: L"*.png;*.jpg")
} KSWV2DialogFilter;

int32_t KSWV2_DialogOpenFile(
    void *hwnd,
    const wchar_t *title,            // NULL 가능
    const wchar_t *default_dir,      // NULL 가능
    const KSWV2DialogFilter *filters, int32_t filter_count,
    int32_t allow_multiple,
    wchar_t ***out_paths,            // KSWV2_Free 각 요소 + 배열
    int32_t *out_count);

int32_t KSWV2_DialogSaveFile(
    void *hwnd,
    const wchar_t *title,
    const wchar_t *default_dir,
    const wchar_t *default_name,
    const KSWV2DialogFilter *filters, int32_t filter_count,
    wchar_t **out_path,              // KSWV2_Free
    int32_t *out_chosen);

int32_t KSWV2_DialogSelectFolder(
    void *hwnd,
    const wchar_t *title,
    const wchar_t *default_dir,
    wchar_t **out_path,              // KSWV2_Free
    int32_t *out_chosen);

#ifdef __cplusplus
}
#endif

#endif // KSWV2_H
