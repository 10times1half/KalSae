//
//  kswv2.h
//  CKalsaeWV2
//
//  Microsoft WebView2 COM SDK 위의 C 전용 API 표면.
//  구현은 kswv2_*.cpp 파일들에 있다. Swift는 이 헤더만 include하고,
//  COM vtable·HRESULT·WRL 관련 코드는 전부 C++ 쪽에 숨긴다.
//
//  스레딩: 이곳의 모든 함수는 호스팅 HWND를 소유한 스레드(Win32 UI
//  스레드)에서 호출되어야 한다. 모든 콜백도 같은 스레드에서 발생한다.
//

#ifndef KSWV2_H
#define KSWV2_H

#include <stdint.h>
#include <wchar.h>
#include "kswv2_taskbar.h"

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - 불투명 핸들 (Opaque handles)
//
// Swift 측은 이 포인터를 불투명 핸들로만 다루며, 내부 구조체에 직접
// 접근하지 않는다. 실제 타입은 ICoreWebView2Environment*,
// ICoreWebView2Controller*, ICoreWebView2* 이며, kswv2_internal.h의
// reinterpret_cast 헬퍼를 통해 변환된다.

typedef struct KSWV2EnvOpaque        *KSWV2Env;
typedef struct KSWV2ControllerOpaque *KSWV2Controller;
typedef struct KSWV2WebViewOpaque    *KSWV2WebView;

// MARK: - 콜백 시그니처
//
// 모든 콜백은 등록 시 전달한 `user` 포인터를 다시 받는다.
// `hr`은 Win32 HRESULT(32비트 부호)이며, 콜백은 반드시 UI 스레드에서 발생한다.
// 콜백 인자 중 포인터가 가리키는 데이터는 콜백 호출 중에만 유효하므로,
// 이후에도 사용하려면 반드시 복사해야 한다.

/// 환경 생성 완료 콜백.
/// `env`는 성공 시 유효한 KSWV2Env이며, 실패 시 NULL이다.
typedef void (*KSWV2EnvCompletedCB)(
    void *user, int32_t hr, KSWV2Env env);

/// 컨트롤러 생성 완료 콜백.
/// `controller`는 성공 시 유효한 KSWV2Controller이며, 실패 시 NULL이다.
typedef void (*KSWV2ControllerCompletedCB)(
    void *user, int32_t hr, KSWV2Controller controller);

/// WebView2 → Swift 메시지 수신 콜백.
/// `message_utf16`는 NUL 종료 UTF-16 JSON 문자열로, WebView2가 소유한다.
/// 콜백 동안만 유효하므로 유지하려면 복사해야 한다.
typedef void (*KSWV2MessageCB)(
    void *user, const wchar_t *message_utf16);

/// 탐색 완료 콜백.
/// `is_success`는 0(실패) 또는 1(성공)이다.
typedef void (*KSWV2NavigationCompletedCB)(
    void *user, int32_t hr, int32_t is_success);

// MARK: - 환경 (Environment)

/// `WebView2Loader.dll`을 `LoadLibraryW` 하기 전에 검색 경로 맨 앞에
/// 끼워 넣을 디렉터리를 등록한다. 첫 번째 환경 생성(`KSWV2_CreateEnvironment`
/// 또는 `KSWV2_GetAvailableBrowserVersion`) **이전에만** 효과가 있다.
/// `dir`이 NULL이면 아무 일도 하지 않는다. 동일 호출은 한 번만 적용되는
/// InitOnce 보호하의 단발성 설정이다.
void KSWV2_SetLoaderSearchDirectory(const wchar_t *dir);

/// WebView2 환경을 생성한다. 완료 시 `completed` 콜백이 호출된다.
/// `browser_executable_folder`: 특정 브라우저 바이너리 경로 (NULL = 기본)
/// `user_data_folder`: 사용자 데이터 디렉터리 (NULL = 기본)
int32_t KSWV2_CreateEnvironment(
    const wchar_t *browser_executable_folder,   // NULL 가능
    const wchar_t *user_data_folder,            // NULL 가능
    void *user,
    KSWV2EnvCompletedCB completed);

/// 확장 환경 옵션 묶음. 사용하지 않는 필드는 모두 NULL 또는 -1(트라이스테이트)로
/// 두면 SDK 기본값이 적용된다.
///
/// 트라이스테이트 의미:
///   -1 = 미설정 (SDK 기본값)
///    0 = OFF (FALSE)
///    1 = ON  (TRUE)
typedef struct {
    const wchar_t *additional_browser_arguments;     // NULL 가능
    const wchar_t *language;                          // NULL 가능, BCP-47
    const wchar_t *target_compatible_browser_version; // NULL 가능
    int32_t allow_single_sign_on;                     // 트라이스테이트
    int32_t exclusive_user_data_folder_access;        // 트라이스테이트 (Options2)
    int32_t custom_crash_reporting_enabled;           // 트라이스테이트 (Options3)
    int32_t enable_tracking_prevention;               // 트라이스테이트 (Options5)
} KSWV2EnvOptions;

/// `KSWV2_CreateEnvironment`의 확장판. `opts == NULL`이면 기본 함수와
/// 동등하게 동작한다. ABI 보호를 위해 기존 `KSWV2_CreateEnvironment`는
/// 그대로 유지된다.
int32_t KSWV2_CreateEnvironmentEx(
    const wchar_t *browser_executable_folder,   // NULL 가능
    const wchar_t *user_data_folder,            // NULL 가능
    const KSWV2EnvOptions *opts,                // NULL 가능
    void *user,
    KSWV2EnvCompletedCB completed);

/// 환경 객체의 참조 카운트를 해제한다. NULL 안전.
void KSWV2_Env_Release(KSWV2Env env);

/// `GetAvailableCoreWebView2BrowserVersionString`을 래핑한다.
/// 반환된 `*version_out`은 호출자가 소유하며 `CoTaskMemFree`로
/// 해제해야 한다. 버전 문자열이 필요 없을 때는 `version_out`을 NULL로
/// 줄 수 있다. 성공 시 0, 실패 시 Win32 HRESULT를 반환한다.
int32_t KSWV2_GetAvailableBrowserVersion(
    const wchar_t *browser_executable_folder,   // NULL 가능
    wchar_t **version_out);                     // NULL 가능

// MARK: - 컨트롤러 / WebView

/// 주어진 환경과 부모 HWND에 WebView2 컨트롤러를 생성한다.
/// 완료 시 `completed` 콜백이 호출된다.
int32_t KSWV2_CreateController(
    KSWV2Env env,
    void *hwnd,                                 // 실제로는 HWND
    void *user,
    KSWV2ControllerCompletedCB completed);

/// 컨트롤러의 참조 카운트를 해제한다. NULL 안전.
void         KSWV2_Controller_Release(KSWV2Controller controller);
/// 컨트롤러로부터 WebView 인터페이스를 얻는다.
/// 반환된 포인터는 빌린 참조이므로 AddRef하지 않는다.
KSWV2WebView KSWV2_Controller_GetWebView(KSWV2Controller controller);
/// 컨트롤러의 위치와 크기를 설정한다. (x, y, width, height)
int32_t      KSWV2_Controller_SetBounds(
    KSWV2Controller controller, int32_t x, int32_t y, int32_t w, int32_t h);
/// 컨트롤러의 가시성을 설정한다. 0 = 숨김, 1 = 표시.
int32_t      KSWV2_Controller_SetVisible(
    KSWV2Controller controller, int32_t visible);
/// 컨트롤러를 닫고 관련 리소스를 정리한다.
int32_t      KSWV2_Controller_Close(KSWV2Controller controller);

// MARK: - WebView 작업

/// WebView를 지정된 URL로 탐색한다.
int32_t KSWV2_Navigate(KSWV2WebView webview, const wchar_t *url);

/// 단일 메시지 핸들러를 설치한다. 이후 호출은 이전 핸들러를 대체한다.
/// WebView에서 `window.chrome.webview.postMessage()` 또는
/// `window.external.notify()` 호출 시 트리거된다.
/// S_OK(0) 또는 실패 시 HRESULT를 반환한다.
int32_t KSWV2_AddMessageHandler(
    KSWV2WebView webview, void *user, KSWV2MessageCB cb);

/// WebView로 JSON 메시지를 전송한다. WebView 측에서는
/// `window.chrome.webview.addEventListener('message', handler)`로 수신한다.
int32_t KSWV2_PostWebMessageAsJson(
    KSWV2WebView webview, const wchar_t *json_utf16);

/// WebView에서 JavaScript 코드를 실행한다. 결과는 무시된다.
int32_t KSWV2_ExecuteScript(
    KSWV2WebView webview, const wchar_t *script_utf16);

/// WebView2 DevTools 창을 연다.
int32_t KSWV2_OpenDevTools(KSWV2WebView webview);

/// DevTools와 기본 컨텍스트 메뉴를 비활성화하거나 활성화한다.
/// 첫 번째 탐색 전에 호출해야 초기 문서에 적용된다.
int32_t KSWV2_SetDevToolsEnabled(KSWV2WebView webview, int32_t enabled);

/// WebView2 기본 (브라우저 스타일) 컨텍스트 메뉴를 토글한다.
/// DevTools와 독립적; `enabled = 0`은 메뉴만 억제하고 페이지가
/// 자체 메뉴를 렌더링할 수 있도록 한다. 성공 시 0을 반환한다.
int32_t KSWV2_SetDefaultContextMenusEnabled(KSWV2WebView webview, int32_t enabled);

/// 컨트롤러의 `AllowExternalDrop` 플래그를 토글한다 (Runtime 1.0.992+).
/// `allow == 0`이면 WebView는 프로세스 외부 파일 드롭을 거부하고
/// 호스트의 `IDropTarget`이 대신 수신할 수 있게 한다.
int32_t KSWV2_Controller_SetAllowExternalDrop(KSWV2Controller controller, int32_t allow);

// MARK: - 비주얼 / 런타임 튜닝 (Phase C2)
//
// 모두 controller / settings가 이미 생성된 다음에 호출해야 한다.
// 일치하는 인터페이스(`ICoreWebView2Controller2`, `ICoreWebView2Settings5`)를
// 지원하지 않는 런타임 버전에서는 `E_NOINTERFACE`를 그대로 돌려준다.
// 호출자는 이 오류를 무시할 수 있다.

/// 컨트롤러의 기본 배경 색을 설정한다. ARGB 바이트 순서:
/// `a`는 알파 채널, `r/g/b`는 색상 채널 (각 0..255).
/// `a = 0` + 투명 윈도우(`KSWindowConfig.transparent`)를 조합하면
/// WebView 자체를 투명하게 만들 수 있다. `ICoreWebView2Controller2`가 필요하다.
int32_t KSWV2_Controller_SetDefaultBackgroundColor(
    KSWV2Controller controller,
    uint8_t a, uint8_t r, uint8_t g, uint8_t b);

/// 컨트롤러 레벨 줌 배율을 설정한다. `1.0`은 원본; 허용
/// 범위는 WebView2 SDK를 따른다 (약 0.25 ~ 5.0).
int32_t KSWV2_Controller_SetZoomFactor(
    KSWV2Controller controller, double factor);

/// 현재 컨트롤러 줌 배율을 읽는다. 성공 시 0을 반환하고
/// 배율을 `*out_factor`에 쓴다. 두 인수 중 하나라도 NULL이면
/// `E_POINTER`를 반환한다.
int32_t KSWV2_Controller_GetZoomFactor(
    KSWV2Controller controller, double *out_factor);

/// WebView2 설정에서 `IsPinchZoomEnabled`를 토글한다.
/// `ICoreWebView2Settings5`가 필요하다. 성공 시 0, 이전 런타임에서는 `E_NOINTERFACE`.
int32_t KSWV2_SetPinchZoomEnabled(KSWV2WebView webview, int32_t enabled);

// MARK: - WebView2 Settings 토글 (Phase A4)
//
// 모든 함수는 트라이스테이트 정수를 받는다 (-1 = 미설정/no-op, 0 = OFF, 1 = ON).
// 호출자는 한꺼번에 적용하기 위해 묶음 호출 후 결과 HRESULT를 모은다.
// 인터페이스가 미지원이면 `E_NOINTERFACE`를 그대로 반환하므로 호출자는
// 무시할 수 있다.

/// `IsScriptEnabled` (Settings). JavaScript 실행을 제어한다.
int32_t KSWV2_SetScriptEnabled(KSWV2WebView webview, int32_t enabled);

/// `IsStatusBarEnabled` (Settings). 상태 표시줄 표시를 제어한다.
int32_t KSWV2_SetStatusBarEnabled(KSWV2WebView webview, int32_t enabled);

/// `IsZoomControlEnabled` (Settings). Ctrl+/- 줌 제어를 제어한다.
int32_t KSWV2_SetZoomControlEnabled(KSWV2WebView webview, int32_t enabled);

/// `IsBuiltInErrorPageEnabled` (Settings). WebView2 기본 오류 페이지를 제어한다.
int32_t KSWV2_SetBuiltInErrorPageEnabled(KSWV2WebView webview, int32_t enabled);

/// `IsGeneralAutofillEnabled` + `IsPasswordAutosaveEnabled` (Settings4).
/// 두 값을 일괄 토글한다. Settings4가 없으면 `E_NOINTERFACE`.
int32_t KSWV2_SetAutofillEnabled(KSWV2WebView webview, int32_t enabled);

/// `IsSwipeNavigationEnabled` (Settings6). 뒤로/앞으로 스와이프 내비게이션을 제어한다.
int32_t KSWV2_SetSwipeNavigationEnabled(KSWV2WebView webview, int32_t enabled);

/// `IsReputationCheckingRequired` (Settings9). SmartScreen 평판 확인을 제어한다.
int32_t KSWV2_SetReputationCheckingRequired(KSWV2WebView webview, int32_t enabled);

// MARK: - 인쇄 (Phase D1)
//
// `kind`: 0 = 브라우저 스타일 인쇄 미리보기 (COREWEBVIEW2_PRINT_DIALOG_KIND_BROWSER),
//         1 = OS 시스템 인쇄 대화상자 (COREWEBVIEW2_PRINT_DIALOG_KIND_SYSTEM).
// 동기 호출. 반환값은 HRESULT. 런타임이 ICoreWebView2_16을 지원하지
// 않으면 E_NOINTERFACE를 돌려준다.
int32_t KSWV2_ShowPrintUI(KSWV2WebView webview, int32_t kind);

// MARK: - 캡처 미리보기 (Phase D3)
//
// `format`: 0 = PNG, 1 = JPEG.
// 콜백은 UI 스레드에서 1회 발생한다. `data`/`len`은 콜백 동안만 유효하며
// Swift 측은 즉시 복사해야 한다. 호출 자체가 실패하면(`E_POINTER` 등)
// 콜백은 호출되지 않으므로 수신측에서 retain한 박스를 직접 해제해야 한다.
typedef void (*KSWV2CaptureCB)(
    void *user, int32_t hr,
    const uint8_t *data, size_t len);

/// WebView의 현재 화면을 캡처한다. 결과는 PNG 또는 JPEG 바이너리로 콜백에 전달된다.
int32_t KSWV2_CapturePreview(
    KSWV2WebView webview, int32_t format,
    void *user, KSWV2CaptureCB cb);

// MARK: - 네이티브 파일 드래그 앤 드롭 (IDropTarget)
//
// `KSWV2_Controller_SetAllowExternalDrop(controller, 0)`과 호스트 HWND에
// `KSWV2_RegisterDropTarget`을 같이 쓰면 OS 파일 드롭이 WebView2
// 자식을 건너뛰고 호스트 측 이벤트로 올라온다. 이 shim은 vtable을 C++에
// 숨긴 IDropTarget COM 객체를 감싸고, Swift 쪽에는 아래 C 콜백만 노출한다.
//
// 스레딩: 콜백은 UI 스레드에서 발생한다(OLE 드롭 매니저가 일반 메시지
// 큐를 통해 디스패치). `paths`와 내부 문자열의 수명은 콜백 동안만 유효하다.

/// `KSWV2DropCB`가 보고하는 드롭 이벤트 종류.
typedef enum {
    KSWV2_DropEvent_Enter = 0,   // 드롭 가능한 데이터가 HWND 영역에 진입
    KSWV2_DropEvent_Leave = 1,   // 드래그가 취소되거나 영역을 벗어남
    KSWV2_DropEvent_Drop  = 2,   // 사용자가 실제로 파일을 놓음
} KSWV2DropEventKind;

/// 드롭 콜백. `paths`는 `paths_count`개의 UTF-16 문자열 배열이다.
/// `KSWV2_DropEvent_Leave` 시 배열은 NULL이고 개수는 0이다.
/// `screen_x` / `screen_y`는 화면 좌표(POINTL)이다.
///
/// 0을 반환하면 수락 (DROPEFFECT_COPY), 0이 아니면 거부
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
/// 필요하다. S_OK / S_FALSE 시 0, 그 외에는 `OleInitialize`의 HRESULT를 반환한다.
int32_t KSWV2_OleInitializeOnce(void);

/// `hwnd`에 `IDropTarget`을 설치한다. 이전에 이 함수로 설치된
/// 드롭 타겟을 대체한다. 성공 시 0 (S_OK)을 반환한다.
int32_t KSWV2_RegisterDropTarget(
    void *hwnd, void *user, KSWV2DropCB cb);

/// `hwnd`의 드롭 타겟을 해제한다. 등록된 타겟이 없는 HWND에도 안전하게 호출할 수 있다.
void KSWV2_RevokeDropTarget(void *hwnd);

/// 문서 생성 시 실행할 JavaScript를 등록한다. 이후 모든 탐색에서
/// 해당 스크립트가 자동 실행된다.
int32_t KSWV2_AddScriptToExecuteOnDocumentCreated(
    KSWV2WebView webview, const wchar_t *script_utf16);

/// 탐색 완료 핸들러를 등록한다. 페이지 로딩이 완료될 때마다 호출된다.
int32_t KSWV2_AddNavigationCompletedHandler(
    KSWV2WebView webview, void *user, KSWV2NavigationCompletedCB cb);

// MARK: - 가상 호스트 매핑 (https 가상 호스트를 통한 로컬 파일 제공)
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
// shim이 소유권을 가져가 응답을 조립한 뒤 free()로 해제한다.
typedef int32_t (*KSWV2ResourceCB)(
    void *user,
    const wchar_t *uri,
    uint8_t **out_data,
    size_t *out_len,
    wchar_t **out_content_type,
    wchar_t **out_csp);

/// 웹 리소스 요청 핸들러를 등록한다. 필터와 함께 사용하여 특정 URI 패턴에
/// 대한 요청을 가로채 합성 응답을 반환할 수 있다.
int32_t KSWV2_AddWebResourceRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2ResourceCB cb);

/// URI 와일드카드 패턴(예: `"https://app.kalsae/*"`)을 필터 목록에 추가한다.
/// 여러 필터는 OR 조건으로 결합된다.
/// `KSWV2_AddWebResourceRequestedHandler` 이후에 호출해야 한다.
int32_t KSWV2_AddWebResourceRequestedFilter(
    KSWV2WebView webview, const wchar_t *uri_wildcard);

/// 이 WebView의 자산 응답에 Cross-Origin Isolation 헤더(COOP/COEP/CORP)를
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

/// 새 창(팝업) 요청 핸들러.
/// `window.open()` / `target="_blank"` 등으로 WebView2가 새 창을
/// 열려할 때 호출된다.
/// 콜백 반환값: 0 = 요청 거부 (Handled=TRUE, NewWindow=null),
///              그 외 = 허용 (호스트가 직접 NewWindow 처리 필요).
/// uri_utf16: 요청된 목적지 URL (항상 non-null).
typedef int32_t (*KSWV2NewWindowCB)(void *user, const wchar_t *uri_utf16);

/// 새 창 요청 핸들러를 등록한다. 팝업 차단에 사용된다.
int32_t KSWV2_AddNewWindowRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2NewWindowCB cb);

/// 권한 요청 핸들러.
/// 마이크, 카메라, 지오로케이션 등 민감한 API 요청 시 호출된다.
/// kind는 COREWEBVIEW2_PERMISSION_KIND 정수값.
/// 콜백 반환값: 0 = DENY, 1 = ALLOW, 2 = DEFAULT (WebView2 기본 처리).
typedef int32_t (*KSWV2PermissionCB)(
    void *user, const wchar_t *uri_utf16, int32_t kind);

/// 권한 요청 핸들러를 등록한다.
int32_t KSWV2_AddPermissionRequestedHandler(
    KSWV2WebView webview, void *user, KSWV2PermissionCB cb);

/// 다운로드 시작 핸들러 (ICoreWebView2_4).
/// 페이지가 파일 다운로드를 시작할 때 호출된다.
/// url_utf16:  다운로드 URL.
/// mime_utf16: MIME 타입 (없으면 빈 문자열).
/// 콜백 반환값: 0 = 다운로드 허용, 1 = 취소.
typedef int32_t (*KSWV2DownloadStartingCB)(
    void *user, const wchar_t *url_utf16, const wchar_t *mime_utf16);

/// 다운로드 시작 핸들러를 등록한다.
int32_t KSWV2_AddDownloadStartingHandler(
    KSWV2WebView webview, void *user, KSWV2DownloadStartingCB cb);

/// TLS/서버 인증서 오류 핸들러 (ICoreWebView2_14).
/// 콜백 반환값: 0 = 탐색 취소(deny-secure 기본값), 1 = 계속(허용).
/// 지원하지 않는 런타임에서 KSWV2_AddServerCertificateErrorHandler는
/// E_NOINTERFACE를 반환하며 핸들러가 설치되지 않는다.
typedef int32_t (*KSWV2ServerCertErrorCB)(void *user);

/// 서버 인증서 오류 핸들러를 등록한다.
int32_t KSWV2_AddServerCertificateErrorHandler(
    KSWV2WebView webview, void *user, KSWV2ServerCertErrorCB cb);

/// HTTP Basic/Digest 인증 요청 핸들러 (ICoreWebView2_10).
/// 콜백 반환값: 0 = 취소(자격증명 없이 거부), 1 = 계속(기본 처리).
/// 기본 정책: 취소(0). 지원하지 않는 런타임에서 E_NOINTERFACE.
typedef int32_t (*KSWV2BasicAuthCB)(
    void *user, const wchar_t *uri_utf16, const wchar_t *challenge_utf16);

/// HTTP 기본 인증 요청 핸들러를 등록한다.
int32_t KSWV2_AddBasicAuthenticationHandler(
    KSWV2WebView webview, void *user, KSWV2BasicAuthCB cb);

/// 클라이언트 인증서 요청 핸들러 (ICoreWebView2_5).
/// 콜백 반환값: 0 = 취소(인증서 없이 진행), 1 = 기본 처리(OS 선택기).
/// 기본 정책: 취소(0). 지원하지 않는 런타임에서 E_NOINTERFACE.
typedef int32_t (*KSWV2ClientCertCB)(void *user, const wchar_t *host_utf16);

/// 클라이언트 인증서 요청 핸들러를 등록한다.
int32_t KSWV2_AddClientCertificateHandler(
    KSWV2WebView webview, void *user, KSWV2ClientCertCB cb);


//
// Swift가 반환하는 응답 버퍼는 C++ 쪽에서 `free()`할 수 있어야 한다.
// Swift의 자체 할당자가 CRT 할당자와 일치한다는 보장이 없으므로, 콜백이
// 이 헬퍼를 통해 할당한다. 이는 shim이 링크한 같은 CRT의 `malloc` /
// `_wcsdup`을 그대로 감싼 것이다.

/// CRT malloc을 감싼 할당자. Swift 측에서 할당한 메모리를 C++ 쪽에서
/// free할 수 있도록 동일 CRT를 사용한다.
void    *KSWV2_Alloc(size_t n);
/// CRT free를 감싼 해제자. NULL 안전.
void     KSWV2_Free(void *p);
/// 주어진 길이의 와이드 문자열을 CRT malloc으로 복사한다.
wchar_t *KSWV2_WcsDupCopy(const wchar_t *src, size_t len);

// MARK: - WinRT 토스트 알림 (Toast Notifications)

/// 호출 프로세스의 AppUserModelID를 설정한다.
/// 토스트 알림이 애플리케이션의 시작 메뉴 바로 가기와 연결되려면 필요하다.
/// 성공 시 0 (S_OK)을 반환한다.
int32_t KSWV2_SetAppUserModelID(const wchar_t *aumid);

/// Windows.UI.Notifications XAML 토스트를 `aumid` 하에 표시한다.
/// `title`과 `body`는 선택 사항이다 (NULL 또는 빈 문자열이면 해당 `<text>` 요소 생략).
/// `tag`는 WinRT 토스트 태그로 사용되며, `KSWV2_CancelToast`로 알림을
/// 취소하는 데 사용된다. NULL 또는 빈 문자열을 전달하면 태그 없이 게시된다.
/// 성공 시 0, 실패 시 Win32 HRESULT를 반환한다 (예: AUMID가 시작 메뉴
/// 바로 가기에 등록되지 않은 경우 RPC_E_DISCONNECTED).
int32_t KSWV2_ShowToast(
    const wchar_t *aumid,
    const wchar_t *title,
    const wchar_t *body,
    const wchar_t *tag);

/// `tag`로 식별되는 토스트 알림을 `aumid`의 Action Center 기록에서 제거한다.
/// `IToastNotificationHistory::RemoveGroupedTagWithId`를 빈 그룹으로 호출한다.
/// 제거 성공 또는 일치하는 알림이 없을 때 S_OK(0)를 반환한다.
/// 0이 아닌 반환값은 WinRT 활성화 실패를 나타낸다.
int32_t KSWV2_CancelToast(
    const wchar_t *aumid,
    const wchar_t *tag);

// MARK: - 이미지 변환 (WIC) — PNG ↔ DIB
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
// 일반적인 `CF_DIB` 페이로드다 — `BITMAPFILEHEADER`는 포함되지 않는다.
// 출력 DIB는 32-bpp BGRA, bottom-up이다.

/// PNG 바이너리를 DIB(Device Independent Bitmap) 형식으로 변환한다.
int32_t KSImage_PNGToDIB(
    const uint8_t *png_bytes, size_t png_size,
    uint8_t **out_data, size_t *out_size);

/// DIB 바이너리를 PNG 형식으로 변환한다.
int32_t KSImage_DIBToPNG(
    const uint8_t *dib_bytes, size_t dib_size,
    uint8_t **out_data, size_t *out_size);

// MARK: - 모던 파일 다이얼로그 (IFileOpenDialog / IFileSaveDialog)
//
// 레거시 GetOpenFileNameW / SHBrowseForFolderW를 대체한다. 호스트 HWND를
// 소유한 UI 스레드에서 호출해야 하며, 호출 스레드는 STA로 COM이
// 초기화되어 있어야 한다. 모든 입력 문자열은 NULL 가능하다 (있는 경우만 적용).
//
// 반환값은 HRESULT(0=S_OK). 사용자가 취소하면 S_OK + `*out_count == 0`
// 또는 `*out_chosen == 0`이 돌아온다.
//
// 출력 문자열은 KSWV2_WcsDupCopy로 할당되었으므로 호출자는 KSWV2_Free로
// 각 문자열을 해제해야 하며, OpenFile의 배열도 KSWV2_Free로 해제한다.

/// 파일 다이얼로그의 필터를 정의하는 구조체.
typedef struct {
    const wchar_t *name;     // 표시 이름 (예: L"이미지 파일")
    const wchar_t *spec;     // 패턴 — 세미콜론 구분 (예: L"*.png;*.jpg")
} KSWV2DialogFilter;

/// 파일 열기 다이얼로그를 표시한다. 다중 선택이 가능하다.
int32_t KSWV2_DialogOpenFile(
    void *hwnd,
    const wchar_t *title,            // NULL 가능
    const wchar_t *default_dir,      // NULL 가능
    const KSWV2DialogFilter *filters, int32_t filter_count,
    int32_t allow_multiple,
    wchar_t ***out_paths,            // KSWV2_Free 각 요소 + 배열
    int32_t *out_count);

/// 파일 저장 다이얼로그를 표시한다.
int32_t KSWV2_DialogSaveFile(
    void *hwnd,
    const wchar_t *title,
    const wchar_t *default_dir,
    const wchar_t *default_name,
    const KSWV2DialogFilter *filters, int32_t filter_count,
    wchar_t **out_path,              // KSWV2_Free
    int32_t *out_chosen);

/// 폴더 선택 다이얼로그를 표시한다.
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
