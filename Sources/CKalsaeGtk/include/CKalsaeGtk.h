/*
 * CKalsaeGtk - Swift와 GTK4 + WebKitGTK 6.0 사이를 이어주는 얇은 C 글루 계층.
 *
 * Swift 쪽 코드는 (`CKalsaeGtk` 헤더를 통해) 이 모듈을 가져다가
 * 복잡한 GObject 시그널/콜백 배선을 피해서, Swift 계층이 작고
 * `@convention(c)` 없이 유지될 수 있도록 한다.
 */
#ifndef CKALSAE_GTK_H
#define CKALSAE_GTK_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KSGtkHost KSGtkHost;

/** 수신 메시지 콜백. `json`은 UTF-8 NUL 종료 문자열이며;
 *  콜백이 반환할 때 수명이 끝난다 — Swift 캣이 유지해야
 *  한다면 직접 복사해야 한다.                                     */
typedef void (*KSGtkMessageFn)(const char *json, void *ctx);

/** 활성화 콜백. 운영중인 GtkApplication이 윈도우를 만들고
 *  탐색 준비가 된 후 메인 스레드에서 호출된다.   */
typedef void (*KSGtkActivateFn)(void *ctx);

/* 생명주기 -------------------------------------------------------- */

/** 초기화되지 않은 호스트를 생성한다. 윈도우는
 *  GtkApplication의 "activate" 시그널 시점에 생성된다.             */
KSGtkHost *ks_gtk_host_new(const char *app_id,
                           const char *title,
                           int width,
                           int height);

/** 호스트를 파괴하고 GObject를 해제한다. 부분 초기화된
 *  호스트에도 안전하게 호출할 수 있다.                                     */
void ks_gtk_host_free(KSGtkHost *host);

/** 스크립트 메시지 핸들러를 등록한다. 첫 번째
 *  로드 전에 사용자 콘텐츠 매니저가 설치할 수 있도록
 *  `ks_gtk_host_run` 전에 호출해야 한다.                                     */
void ks_gtk_host_set_message_handler(KSGtkHost *host,
                                     KSGtkMessageFn cb,
                                     void *ctx);

/** 윈도우+웹뷰가 메인 스레드에서 생성된 후 한 번 호출되는
 *  활성화 콜백을 등록한다. Swift는 이를 사용해 초기
 *  탐색을 예약한다.                                         */
void ks_gtk_host_set_on_activate(KSGtkHost *host,
                                 KSGtkActivateFn cb,
                                 void *ctx);

/** document-start에 주입할 사용자 스크립트를 큐에 담는다.           */
void ks_gtk_host_add_user_script(KSGtkHost *host, const char *source);

/* 런타임 — 활성화 이후 호출 가능 ------------------------------- */

/** `uri`로 내장된 WebKitWebView를 탐색한다. http(s) 및
 *  file:// URI가 모두 지원된다.                                     */
void ks_gtk_host_load_uri(KSGtkHost *host, const char *uri);

/** 웹뷰의 메인 프레임에서 `script`를 실행한다. 실행 후 결과를
 *  기다리지 않음; 오류는 stderr에 로그된다.                                    */
void ks_gtk_host_eval_js(KSGtkHost *host, const char *script);

/** 웹 인스펙터를 활성화한다 (컨텍스트 메뉴의 "요소 조사"). */
void ks_gtk_host_open_devtools(KSGtkHost *host);

/** 윈도우 제목을 업데이트한다. 활성화 전에 호출하면 값을
 *  저장하고 윈도우 생성 시 적용한다. */
void ks_gtk_host_set_title(KSGtkHost *host, const char *title);

/** 윈도우 기본 크기를 업데이트한다. 활성화 전에 호출하면 값을
 *  저장하고 윈도우 생성 시 적용한다. */
void ks_gtk_host_set_size(KSGtkHost *host, int width, int height);

/** 윈도우를 표시/표시한다. 윈도우가 아직 생성되지 않은 경우 아무 조작도 안 한다. */
void ks_gtk_host_show(KSGtkHost *host);

/** 윈도우를 숨긴다. 윈도우가 아직 생성되지 않은 경우 아무 조작도 안 한다. */
void ks_gtk_host_hide(KSGtkHost *host);

/** 윈도우를 표시하여 포커스를 요청한다. */
void ks_gtk_host_focus(KSGtkHost *host);

/** 현재 로드된 페이지가 있으면 다시 로드한다. */
void ks_gtk_host_reload(KSGtkHost *host);

/** 윈도우를 최소화한다. */
void ks_gtk_host_minimize(KSGtkHost *host);

/** 윈도우를 최대화한다. */
void ks_gtk_host_maximize(KSGtkHost *host);

/** 윈도우를 최대화 상태에서 복원한다. */
void ks_gtk_host_unmaximize(KSGtkHost *host);

/** 최대화되어 있으면 1, 아니면 0을 반환한다. */
int ks_gtk_host_is_maximized(KSGtkHost *host);

/** 최소화/아이콘화되어 있으면 1, 아니면 0을 반환한다.
 *  최소화 상태를 노출하지 않는 컴포지터에서는 0을 반환한다. */
int ks_gtk_host_is_minimized(KSGtkHost *host);

/** 전체화면 모드로 진입한다. */
void ks_gtk_host_fullscreen(KSGtkHost *host);

/** 전체화면 모드에서 빠져나온다. */
void ks_gtk_host_unfullscreen(KSGtkHost *host);

/** 전체화면이면 1, 아니면 0을 반환한다. */
int ks_gtk_host_is_fullscreen(KSGtkHost *host);

/** 현재 위젯 너비/높이를 out 파라미터에 쓴다.
 *  성공 시 1, 사용 불가 시 0을 반환한다. */
int ks_gtk_host_get_size(KSGtkHost *host, int *out_width, int *out_height);

/* 클립보드 ----------------------------------------------------------- */

/** 화면 클립보드에 UTF-8 텍스트를 쓴다. 활성화 후에
 *  윈도우가 실체화된 다음에 호출해야 한다. */
void ks_gtk_clipboard_write_text(KSGtkHost *host, const char *text);

/** 화면 클립보드를 지운다. */
void ks_gtk_clipboard_clear(KSGtkHost *host);

/** UTF-8 텍스트를 비동기로 읽는다. GTK 메인 스레드에서
 *  텍스트(비어 있거나 지원되지 않으면 NULL 가능)와 `ctx`를 인수로
 *  `cb`를 호출한다.  */
typedef void (*KSGtkClipboardTextFn)(const char *text, void *ctx);
void ks_gtk_clipboard_read_text(KSGtkHost *host,
                                KSGtkClipboardTextFn cb,
                                void *ctx);

/** 클립보드에 평문이 있으면 1, 아니면 0을 반환한다.    */
int ks_gtk_clipboard_has_text(KSGtkHost *host);

/* 클립보드 이미지 --------------------------------------------------- */

/** 이미지 읽기 결과 콜백. `bytes`는 PNG 데이터 (`len` 바이트)를
 *  담는다; 실패 시 둘 다 NULL/0일 수 있다. `bytes`의 수명은
 *  콜백이 반환할 때까지 유효하며 필요하면 복사해야 한다.   */
typedef void (*KSGtkClipboardImageFn)(const uint8_t *bytes,
                                      size_t len,
                                      void *ctx);

/** 원시 PNG 바이트를 GdkTexture로서 화면 클립보드에 쓴다.
 *  성공 시 1, 실패 시 0(PNG 오류 또는 윈도우 없음).  */
int ks_gtk_clipboard_write_png(KSGtkHost *host,
                                const uint8_t *png_bytes,
                                size_t png_len);

/** 클립보드 이미지를 PNG 바이트로 비동기로 읽는다.
 *  GTK 메인 스레드에서 `cb`를 호출한다. 이미지가 없으면
 *  `bytes`/`len`은 NULL/0이다.                                    */
void ks_gtk_clipboard_read_png(KSGtkHost *host,
                                KSGtkClipboardImageFn cb,
                                void *ctx);

/** 클립보드에 이미지(GdkTexture)가 있으면 1, 아니면 0을 반환한다. */
int ks_gtk_clipboard_has_image(KSGtkHost *host);

/* 다이얼로그 --------------------------------------------------------- */

/** 다중 파일 결과 콜백. `paths`는 NULL 종료된 UTF-8 경로 문자열
 *  배열이거나 취소 시 NULL이다.           */
typedef void (*KSGtkFilesResultFn)(const char *const *paths, void *ctx);

/** 단일 파일/폴더 결과 콜백. `path`는 UTF-8 경로 문자열이거나
 *  취소 시 NULL이다.                           */
typedef void (*KSGtkFileResultFn)(const char *path, void *ctx);

/** 메시지 다이얼로그 결과 콜백.
 *  result: 0 = 첫 번째 버튼 (OK/예), 1 = 두 번째 버튼 (취소/아니오),
 *          2 = 세 번째 버튼 (yesNoCancel의 취소), -1 = 창이 닫힘. */
typedef void (*KSGtkMsgResultFn)(int result, void *ctx);

/** 네이티브 파일 선택기 다이얼로그를 연다(열기 모드).
 *  filter_names / filter_globs는 filter_count 길이의 병렬 배열;
 *  각 glob 엔트리는 패턴의 세미콜론 구분 목록이다 ("*.txt;*.md"). */
void ks_gtk_dialog_open_files(KSGtkHost *host,
                              const char *title,
                              const char *default_dir,
                              const char *const *filter_names,
                              const char *const *filter_globs,
                              int filter_count,
                              int allow_multiple,
                              KSGtkFilesResultFn cb, void *ctx);

/** 네이티브 파일 선택기 다이얼로그를 연다(저장 모드). */
void ks_gtk_dialog_save_file(KSGtkHost *host,
                             const char *title,
                             const char *default_dir,
                             const char *default_name,
                             const char *const *filter_names,
                             const char *const *filter_globs,
                             int filter_count,
                             KSGtkFileResultFn cb, void *ctx);

/** 네이티브 폴더 선택기 다이얼로그를 연다. */
void ks_gtk_dialog_select_folder(KSGtkHost *host,
                                 const char *title,
                                 const char *default_dir,
                                 KSGtkFileResultFn cb, void *ctx);

/** 네이티브 메시지 다이얼로그를 표시한다.
 *  kind:    0=정보  1=경고  2=오류  3=질문
 *  buttons: 0=확인  1=확인/취소  2=예/아니오  3=예/아니오/취소               */
void ks_gtk_dialog_message(KSGtkHost *host,
                           int kind,
                           const char *title,
                           const char *message,
                           const char *detail,
                           int buttons,
                           KSGtkMsgResultFn cb, void *ctx);

/* 메인 루프 ---------------------------------------------------------- */

/** GtkApplication을 종료될 때까지 실행한다. 응용프로그램 종료 코드를
 *  반환한다. 호출 스레드를 블록한다.                                */
int ks_gtk_host_run(KSGtkHost *host, int argc, char **argv);

/** 메인 스레드에서 GtkApplication 종료를 요청한다.
 *  어느 스레드에서도 안전하게 호출할 수 있다.                                 */
void ks_gtk_host_quit(KSGtkHost *host);

/** 메인 스레드에서 `fn(ctx)`를 실행하도록 예약한다. 스레드 안전;
 *  `g_idle_add`로 구현. Task.detached 완료 후 UI 스레드로
 *  돌아오는 데 Swift 브리지가 사용한다.           */
void ks_gtk_post_main_thread(void (*fn)(void *ctx), void *ctx);

/* -- 커스텀 `ks://` 스키마 핸들러 ----------------------------------- */

/** 리졸버 콜백. 성공 시 0, 실패 시 비제로를 반환해야 한다.
 *  성공 시 창주자는 `*out_data`(g_malloc으로 할당, 소유권 이전)를
 *  `*out_len` 바이트로, 선택적으로 `*out_mime`(g_malloc, 소유권 이전)를
 *  할당한다. 실패 시 C 심은 웹뷰에 404로 응답한다.                      */
typedef int (*KSGtkSchemeResolverFn)(const char *path,
                                     void *ctx,
                                     char **out_data,
                                     size_t *out_len,
                                     char **out_mime);

/** `ks://` 커스텀 스키마에 대한 리졸버를 등록한다. 첫 번째
 *  탐색 전에 스키마가 등록되도록 `ks_gtk_host_run` 전에
 *  호출해야 한다.                          */
void ks_gtk_host_set_scheme_resolver(KSGtkHost *host,
                                     KSGtkSchemeResolverFn cb,
                                     void *ctx);

/** 모든 `ks://` 응답에 선택할 Content-Security-Policy를 설정한다.
 *  해제하려면 NULL이나 빈 문자열을 전달한다. 문자열은 복사되며
 *  인수 버퍼의 소유권은 호출자가 유지한다.              */
void ks_gtk_host_set_response_csp(KSGtkHost *host, const char *csp);

/* 고급 WebView/윈도우 제어 ------------------------------------------ */

/** WebKitWebView 줄 배율을 설정한다. 1.0 = 원본.             */
void ks_gtk_host_set_zoom_level(KSGtkHost *host, double level);

/** 현재 WebKitWebView 줄 배율을 반환한다. 사용 불가 시 1.0. */
double ks_gtk_host_get_zoom_level(KSGtkHost *host);

/** WebKitWebView 배경색을 설정한다.
 *  r, g, b, a는 [0.0, 1.0] 범위에 있다.                        */
void ks_gtk_host_set_background_color(KSGtkHost *host,
                                      float r, float g,
                                      float b, float a);

/** GTK 응용프로그램 테마를 설정한다.
 *  theme: 0 = 시스템 (기본값 복원), 1 = 라이트, 2 = 다크.     */
void ks_gtk_host_set_theme(KSGtkHost *host, int theme);

/** gtk_widget_set_size_request로 윈도우의 최소 크기를 설정한다.
 *  제약이 없는 차원에는 0을 전달한다.         */
void ks_gtk_host_set_min_size(KSGtkHost *host, int width, int height);

/** 윈도우의 최대 크기를 설정한다. X11에서는 크기 힌트로 적용;
 *  대부분의 Wayland 컴포지터는 임묵 무시한다.  */
void ks_gtk_host_set_max_size(KSGtkHost *host, int width, int height);

/** 윈도우를 화면 좌표 (x, y)로 이동한다. X11에서는 적용;
 *  Wayland 컴포지터는 윈도우 위치를 제어하므로 무시한다. */
void ks_gtk_host_set_position(KSGtkHost *host, int x, int y);

/** 현재 윈도우 위치를 (*out_x, *out_y)에 읽어 담는다.
 *  성공 시 1, 사용 불가 시 0(Wayland 등)을 반환한다.      */
int ks_gtk_host_get_position(KSGtkHost *host, int *out_x, int *out_y);

/** 기본 모니터의 작업 영역 가운데에 윈도우를 배치한다.         */
void ks_gtk_host_center(KSGtkHost *host);

/** close-request 인터셉터를 활성화/비활성화한다.
 *  활성화 시 OS 닫기 동작이 `__ks.window.beforeClose`를
 *  JS에 전달하고 기본 닫기를 억제한다. enabled: 1=켜짐, 0=꺼짐.  */
void ks_gtk_host_set_close_interceptor(KSGtkHost *host, int enabled);

/** 네이티브 close-request 핸들러. 사용자가 윈도우를 닫으려 할 때
 *  (제목표시줄 X, Alt+F4 등) 메인 스레드에서 동기적으로 호출된다.
 *  닫기를 막으려면 1, 허용하려면 0을 반환한다. */
typedef int (*KSGtkCloseHandlerFn)(void *ctx);

/** 네이티브 close-request 핸들러를 등록한다. 이전 등록을 대체한다.
 *  cb와 ctx를 모두 NULL로 전달하면 해제된다. */
void ks_gtk_host_set_close_handler(KSGtkHost *host,
                                    KSGtkCloseHandlerFn cb,
                                    void *ctx);

/** enabled=1일 때 다른 모든 윈도우 위에 유지하고
 *  enabled=0이면 일반 스태킹으로 복원한다.
 *  Wayland 컴포지터는 이 요청을 임묵 무시할 수 있다.         */
void ks_gtk_host_set_keep_above(KSGtkHost *host, int enabled);

/* ----------------------------------------------------------------
 * 윈도우 상태 영속화 (window state persistence)
 * ---------------------------------------------------------------- */

/** 활성화 전에 적용할 복원 상태를 호스트에 저장한다.
 *  값은 `on_activate`에서 윈도우가 만들어진 직후 적용된다.
 *  has_position이 0이면 위치는 무시되고 기본 배치를 따른다.
 *  Wayland에서는 위치 설정이 임묵 무시될 수 있으나, 크기/최대화/
 *  전체화면은 그대로 적용된다.                                       */
void ks_gtk_host_set_pending_restore_state(KSGtkHost *host,
                                            int x, int y,
                                            int width, int height,
                                            int has_position,
                                            int maximized,
                                            int fullscreen);

/** 현재 윈도우 상태를 출력 파라미터에 채워 넣는다.
 *  성공 시 1, 윈도우가 아직 만들어지지 않은 경우 0을 반환한다.
 *  out_has_position은 위치를 신뢰할 수 있을 때(주로 X11) 1로 설정된다. */
int ks_gtk_host_get_window_state(KSGtkHost *host,
                                  int *out_x, int *out_y,
                                  int *out_width, int *out_height,
                                  int *out_has_position,
                                  int *out_maximized,
                                  int *out_fullscreen);

/** 윈도우 상태 저장 콜백. close-request 시점에 메인 스레드에서
 *  동기적으로 호출되며, has_position이 0이면 호출자는 위치 필드를
 *  무시해야 한다.                                                    */
typedef void (*KSGtkStateSaveFn)(int x, int y,
                                  int width, int height,
                                  int has_position,
                                  int maximized,
                                  int fullscreen,
                                  void *ctx);

/** 윈도우 상태 저장 핸들러를 등록한다. cb=NULL은 등록을 해제한다.
 *  `close_handler`보다 먼저 호출되어, 닫기가 실제로 진행되든 막히든
 *  관계없이 마지막 상태가 디스크에 보존된다.                        */
void ks_gtk_host_set_state_save_handler(KSGtkHost *host,
                                         KSGtkStateSaveFn cb,
                                         void *ctx);

/* ----------------------------------------------------------------
 * 키보드 가속기 (window-scoped)
 * ----------------------------------------------------------------
 * GtkShortcutController(scope=LOCAL)에 단축키를 부착한다. 글로벌
 * 시스템-와이드 단축키는 v1 범위 외이며, 윈도우 포커스가 있을 때만
 * 발동한다.
 */

/** 가속기 활성화 콜백. 메인 스레드에서 호출된다.
 *  사용자가 핸들러로 이벤트가 처리되었다고 보고하려면 1, 그렇지 않으면 0.
 *  현재 구현은 항상 1을 반환하도록 가정한다(이벤트 소비). */
typedef int (*KSGtkAcceleratorFn)(void *ctx);

/** GTK 트리거 문자열(`<Control><Shift>n` 형태)을 파싱해 윈도우의
 *  shortcut controller에 등록한다. 같은 id가 이미 있으면 먼저 제거한다.
 *  성공 시 1, 트리거 파싱 실패 시 0을 반환한다. */
int ks_gtk_host_install_accelerator(KSGtkHost *host,
                                     const char *id,
                                     const char *trigger,
                                     KSGtkAcceleratorFn cb,
                                     void *ctx);

/** id에 대응하는 단축키를 제거한다. id가 없으면 no-op. */
void ks_gtk_host_uninstall_accelerator(KSGtkHost *host, const char *id);

/** 이 호스트에 등록된 모든 단축키를 제거한다. */
void ks_gtk_host_uninstall_all_accelerators(KSGtkHost *host);

/* ----------------------------------------------------------------
 * D-Bus logind power monitoring (suspend / resume)
 * ---------------------------------------------------------------- */

/** 전원 이벤트 콜백. 메인 스레드에서 호출된다.             */
typedef void (*KSGtkPowerFn)(void *ctx);

/** 일시 중단 콜백을 등록한다.  아직 설치되지 않았다면
 *  `ks_gtk_host_install_power_monitor`를 자동으로 호출한다.  */
void ks_gtk_host_set_on_suspend(KSGtkHost *host,
                                 KSGtkPowerFn cb,
                                 void *ctx);

/** 재개 콜백을 등록한다.  아직 설치되지 않았다면
 *  `ks_gtk_host_install_power_monitor`를 자동으로 호출한다.  */
void ks_gtk_host_set_on_resume(KSGtkHost *host,
                                KSGtkPowerFn cb,
                                void *ctx);

/** D-Bus 시스템 버스의 `org.freedesktop.login1.Manager.PrepareForSleep`
 *  시그널을 구독한다. 이미 구독 중이거나 두 콜백이 모두 NULL이면
 *  아무 조작도 안 한다. 시스템 버스가 없는 환경(컨테이너 등)에서는
 *  임묵 건너뛴다.     */
void ks_gtk_host_install_power_monitor(KSGtkHost *host);

/** PrepareForSleep 시그널 구독을 해제하고 D-Bus 커넥션을 해제한다.
 *  `ks_gtk_host_free`에서 자동으로 호출된다. */
void ks_gtk_host_remove_power_monitor(KSGtkHost *host);

/** 내장된 WebView의 플랫폼 인쇄 UI를 연다.
 *  system_dialog: 1 = OS 인쇄 다이얼로그, 0 = 조용한/기본 인쇄.  */
void ks_gtk_host_show_print_ui(KSGtkHost *host, int system_dialog);

/** 현재 WebView 콘텐츠를 PNG 바이트로 캡처한다.
 *  메인 스레드에서 원시 PNG 바이트와 의 길이를
 *  인수로 `cb`를 호출한다. 실패 시 `bytes`는 NULL일 수 있다. `ctx`는
 *  변경 없이 전달된다. 수신측은 `bytes`를 해제하면 안 된다 — 수명은
 *  콜백이 반환할 때 끝난다.
 *  format: 0 = PNG (유일 지원 포맷; JPEG는 PNG를 반환).     */
typedef void (*KSGtkSnapshotResultFn)(const uint8_t *bytes,
                                      size_t len,
                                      void *ctx);
void ks_gtk_host_capture_preview(KSGtkHost *host,
                                 int format,
                                 KSGtkSnapshotResultFn cb,
                                 void *ctx);

/* ================================================================
 * 메뉴 (GMenuModel + GtkPopoverMenuBar / GtkPopoverMenu)
 *
 * 메뉴 항목은 push/pop 토큰으로 트리를 인코딩하는
 * `KSMenuEntry` 값의 FLAT ARRAY로 전달된다:
 *
 *   kind 0  액션        (label + action_id 필수)
 *   kind 1  구분선     (label / action_id 무시)
 *   kind 2  서브메뉴 시작 (label = 서브메뉴 제목)
 *   kind 3  서브메뉴 끝
 *   kind 4  섹션 시작   (label = 선택적 섹션 제목)
 *   kind 5  섹션 끝
 *
 * 모든 문자열 포인터는 UTF-8 NUL 종료이며 `ks_gtk_host_install_menu` /
 * `ks_gtk_host_show_context_menu` 호출 동안만 유효하면 된다.
 * ================================================================ */

typedef struct KSMenuEntry {
    int         kind;        /* 0..5 위와 동일 */
    const char *label;       /* NUL 종료, NULL 가능 */
    const char *action_id;   /* NUL 종료, NULL 가능 */
    int         enabled;     /* 1 = 활성화 */
    int         checked;     /* 1 = 체크마크 있음 */
} KSMenuEntry;

/** 액션 활성화 콜백. `action_id`는 엔트리에 제공된 id와 일치하며;
 *  `ctx`는 변경 없이 전달된다.                        */
typedef void (*KSGtkMenuActivateFn)(const char *action_id, void *ctx);

/** 윈도우에 메뉴 바를 설치한다. 이전 메뉴 바를 대체한다.
 *  `entries`는 호출 반환 후 유지되지 않으며 읽기 전용이다.     */
void ks_gtk_host_install_menu(KSGtkHost *host,
                               const KSMenuEntry *entries,
                               int entry_count,
                               KSGtkMenuActivateFn cb,
                               void *ctx);

/** 위젯 로컬 좌표 `(x, y)`에 일시성 팝오버 컨텍스트 메뉴를 표시한다.
 *  `entries`는 호출 반환 후 유지되지 않으며 읽기 전용이다.  */
void ks_gtk_host_show_context_menu(KSGtkHost *host,
                                    const KSMenuEntry *entries,
                                    int entry_count,
                                    int x, int y,
                                    KSGtkMenuActivateFn cb,
                                    void *ctx);

/* ================================================================
 * 시스템 트레이 (StatusNotifierItem + DBusMenu)
 * ================================================================
 * KDE freedesktop StatusNotifierItem 사양과 com.canonical.dbusmenu
 * 인터페이스를 D-Bus 세션 버스에 직접 노출한다. AppIndicator3 /
 * libayatana 의존성을 도입하지 않고 GIO `GDBusConnection`만 사용한다.
 *
 * 동작하는 데스크톱 환경: KDE Plasma, Cinnamon, XFCE, Pantheon,
 * AppIndicator extension이 설치된 GNOME. Watcher 부재 시 install은
 * 실패하지 않고 no-op로 폴백한다(install_rc=0 반환).
 *
 * 메뉴 항목은 평탄한 배열로 전달된다(서브메뉴 미지원, v1 스코프).
 */

typedef struct KSGtkTray KSGtkTray;

/** 트레이 메뉴 항목. command_id는 활성화 시 콜백에 전달되는
 *  비공개 식별자이며, 빈 문자열은 구분선을 의미한다. */
typedef struct KSGtkTrayMenuItem {
    const char *label;       /* UTF-8, 구분선이면 NULL/"" */
    const char *command_id;  /* UTF-8, 빈 문자열이면 inert */
    int         enabled;     /* 0 = 비활성, 1 = 활성 */
    int         is_separator;/* 1이면 다른 필드 무시 */
} KSGtkTrayMenuItem;

/** 트레이 활성화 콜백. command_id가 비어 있으면 좌클릭/Activate
 *  이벤트를 의미한다(SNI Activate). 메인 스레드에서 호출된다. */
typedef void (*KSGtkTrayActivateFn)(const char *command_id, void *ctx);

/** 새 트레이 인스턴스를 생성한다. 아직 D-Bus에는 등록되지 않으며,
 *  `ks_gtk_tray_install` 호출 시 등록된다. */
KSGtkTray *ks_gtk_tray_new(void);

/** D-Bus 세션 버스에 SNI/DBusMenu 객체를 등록하고 watcher에
 *  RegisterStatusNotifierItem 호출을 시도한다.
 *  성공 시 1, watcher 부재/버스 연결 실패/이미 등록됨이면 0. */
int ks_gtk_tray_install(KSGtkTray *tray,
                         const char *app_id,
                         const char *icon_path,
                         const char *tooltip,
                         const KSGtkTrayMenuItem *items,
                         int item_count,
                         KSGtkTrayActivateFn cb,
                         void *ctx);

/** 툴팁만 갱신한다. 등록되지 않은 상태에서는 다음 install에 반영. */
void ks_gtk_tray_set_tooltip(KSGtkTray *tray, const char *tooltip);

/** 메뉴를 갱신한다(전체 교체). LayoutUpdated 시그널을 emit한다. */
void ks_gtk_tray_set_menu(KSGtkTray *tray,
                           const KSGtkTrayMenuItem *items,
                           int item_count);

/** D-Bus 등록을 해제한다. 이미 해제되었으면 no-op. */
void ks_gtk_tray_remove(KSGtkTray *tray);

/** 트레이 인스턴스를 파괴한다(자동으로 remove를 호출). */
void ks_gtk_tray_free(KSGtkTray *tray);

#ifdef __cplusplus
}
#endif

#endif /* CKALSAE_GTK_H */
