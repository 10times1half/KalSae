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

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KSGtkHost KSGtkHost;

/** Inbound message callback. `json` is a UTF-8 NUL-terminated string;
 *  its lifetime ends when the callback returns ??the Swift side must
 *  copy if it needs to retain.                                     */
typedef void (*KSGtkMessageFn)(const char *json, void *ctx);

/** Activation callback. Invoked on the main thread once the underlying
 *  GtkApplication has created the window and is ready to navigate.   */
typedef void (*KSGtkActivateFn)(void *ctx);

/* 생명주기 -------------------------------------------------------- */

/** Creates an uninitialized host. Does NOT construct the window yet ??
 *  that happens on GtkApplication's "activate" signal.             */
KSGtkHost *ks_gtk_host_new(const char *app_id,
                           const char *title,
                           int width,
                           int height);

/** Destroys the host and releases its GObjects. Safe to call on a
 *  partially-initialized host.                                     */
void ks_gtk_host_free(KSGtkHost *host);

/** Registers the script message handler. Must be called before
 *  `ks_gtk_host_run` so that the user content manager installs it
 *  before the first page load.                                     */
void ks_gtk_host_set_message_handler(KSGtkHost *host,
                                     KSGtkMessageFn cb,
                                     void *ctx);

/** Registers an activation callback invoked once the window + webview
 *  are constructed on the main thread. Swift uses this to schedule
 *  the initial navigation.                                         */
void ks_gtk_host_set_on_activate(KSGtkHost *host,
                                 KSGtkActivateFn cb,
                                 void *ctx);

/** Queues a user script for injection at document-start.           */
void ks_gtk_host_add_user_script(KSGtkHost *host, const char *source);

/* 런타임 — 활성화 이후 호출 가능 ------------------------------- */

/** Navigates the embedded WebKitWebView to `uri`. Both http(s) and
 *  file:// URIs are supported.                                     */
void ks_gtk_host_load_uri(KSGtkHost *host, const char *uri);

/** Evaluates `script` in the webview's main frame. Fire-and-forget;
 *  errors are logged to stderr.                                    */
void ks_gtk_host_eval_js(KSGtkHost *host, const char *script);

/** Enables the Web Inspector ("Inspect Element" in context menu). */
void ks_gtk_host_open_devtools(KSGtkHost *host);

/* 메인 루프 ---------------------------------------------------------- */

/** Runs the GtkApplication until quit. Returns the application exit
 *  code. Blocks the calling thread.                                */
int ks_gtk_host_run(KSGtkHost *host, int argc, char **argv);

/** Requests GtkApplication quit on the main thread. Safe to call
 *  from any thread.                                                 */
void ks_gtk_host_quit(KSGtkHost *host);

/** Schedules `fn(ctx)` to run on the main thread. Thread-safe;
 *  implemented with `g_idle_add`. Used by the Swift bridge to hop
 *  back to the UI thread after Task.detached completes.           */
void ks_gtk_post_main_thread(void (*fn)(void *ctx), void *ctx);

/* -- 커스텀 `ks://` 스키마 핸들러 ----------------------------------- */

/** Resolver callback. Must return 0 on success, non-zero on failure.
 *  On success the callee allocates `*out_data` (g_malloc'd, transfers
 *  ownership to the caller) with `*out_len` bytes, and optionally
 *  `*out_mime` (g_malloc'd, transfers ownership). On failure the C
 *  shim responds with a 404 to the web view.                      */
typedef int (*KSGtkSchemeResolverFn)(const char *path,
                                     void *ctx,
                                     char **out_data,
                                     size_t *out_len,
                                     char **out_mime);

/** Registers a resolver for the `ks://` custom scheme. Must be called
 *  before `ks_gtk_host_run` so the scheme is registered on the web
 *  context before the first navigation.                          */
void ks_gtk_host_set_scheme_resolver(KSGtkHost *host,
                                     KSGtkSchemeResolverFn cb,
                                     void *ctx);

/** Sets the Content-Security-Policy sent with every `ks://` response.
 *  Pass NULL or an empty string to clear. The string is copied; the
 *  caller retains ownership of the argument buffer.              */
void ks_gtk_host_set_response_csp(KSGtkHost *host, const char *csp);

#ifdef __cplusplus
}
#endif

#endif /* CKALSAE_GTK_H */
