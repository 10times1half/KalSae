/*
 * CKalsaeGtk.c — Swift <-> GTK4/WebKit 글루 구현.
 *
 * 빌드 대상:
 *   - GTK 4.x
 *   - WebKitGTK 6.0  (`webkit2gtk-6.0` / `webkitgtk-6.0` pkg-config 이름)
 *
 * GObject 시그널 배선을 C에 두어 Swift에서 GCallback 시그니처용
 * `@convention(c)` thunk을 직접 작성하지 않도록 한다.
 */
#include "CKalsaeGtk.h"

#include <gtk/gtk.h>
#include <webkit/webkit.h>
#include <libsoup/soup.h>
#include <glib.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

struct KSGtkHost {
    /* `new` 시점에 측정된 설정값. */
    char       *app_id;
    char       *title;
    int         width;
    int         height;

    /* "activate"에서 채워지는 라이브 GObject들. */
    GtkApplication              *app;
    GtkWindow                   *window;
    WebKitWebView               *web_view;
    WebKitUserContentManager    *user_cm;

    /* 활성화 전 큐에 쌓아둔 사용자 스크립들. */
    GPtrArray   *pending_scripts;   /* gchar* 소유 */

    /* 콜백. */
    KSGtkMessageFn    on_message;
    void             *on_message_ctx;
    KSGtkActivateFn   on_activate;
    void             *on_activate_ctx;

    /* ks:// 스키마 리졸버 (선택). */
    KSGtkSchemeResolverFn scheme_resolver;
    void                 *scheme_resolver_ctx;

    /* 모든 ks:// 응답에 붙여 보낼 Content-Security-Policy. */
    char                 *response_csp;
};

/* -- 헬퍼 -------------------------------------------------------- */

static gchar *dup_string(const char *s)
{
    return s ? g_strdup(s) : NULL;
}

static void clear_string(char **slot)
{
    if (*slot) { g_free(*slot); *slot = NULL; }
}

/* -- 시그널 핸들러 ------------------------------------------------- */

/* 아래 on_app_activate를 위한 전방 선언. */
static void on_kb_scheme_request(WebKitURISchemeRequest *req,
                                 gpointer user_data);

/* WebKit 6.0: "script-message-received::<name>"은 JSCValue를 전달한다. */
static void on_script_message(WebKitUserContentManager *ucm,
                              JSCValue *value,
                              gpointer user_data)
{
    (void) ucm;
    KSGtkHost *host = (KSGtkHost *) user_data;
    if (!host || !host->on_message) return;

    /* JS 값을 JSON으로 직렬화해 Swift 브리지가 Windows/macOS
     * 백엔드와 동일한 와이어 포맷을 받도록 한다. */
    gchar *json = jsc_value_to_json(value, 0);
    if (!json) return;
    host->on_message(json, host->on_message_ctx);
    g_free(json);
}

static void on_app_activate(GtkApplication *app, gpointer user_data)
{
    KSGtkHost *host = (KSGtkHost *) user_data;

    /* 1. 최상위 윈도우 생성. */
    GtkWindow *win = GTK_WINDOW(gtk_application_window_new(app));
    gtk_window_set_title(win, host->title ? host->title : "Kalsae");
    gtk_window_set_default_size(win, host->width, host->height);

    /* 2. 사용자 콘텐츠 매니저를 생성하고 스크립 핸들러를 연결한다. */
    WebKitUserContentManager *ucm = webkit_user_content_manager_new();

    /* 큐에 쌓인 사용자 스크립들을 배출한다. */
    if (host->pending_scripts) {
        for (guint i = 0; i < host->pending_scripts->len; ++i) {
            const char *src =
                (const char *) g_ptr_array_index(host->pending_scripts, i);
            WebKitUserScript *script = webkit_user_script_new(
                src,
                WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
                WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
                NULL, NULL);
            webkit_user_content_manager_add_script(ucm, script);
            webkit_user_script_unref(script);
        }
    }

    /* "ks" 스크립 메시지 핸들러 등록. */
    webkit_user_content_manager_register_script_message_handler(
        ucm, "ks", NULL);
    g_signal_connect(ucm,
                     "script-message-received::kb",
                     G_CALLBACK(on_script_message),
                     host);

    /* 3. UCM에 연결된 WebKitWebView를 생성해 윈도우의
     *    자식으로 설치한다. */
    WebKitWebView *view = WEBKIT_WEB_VIEW(g_object_new(
        WEBKIT_TYPE_WEB_VIEW,
        "user-content-manager", ucm,
        NULL));

    gtk_window_set_child(win, GTK_WIDGET(view));
    gtk_window_present(win);

    host->window   = win;
    host->web_view = view;
    host->user_cm  = ucm;

    /* 웹 컨텍스트에 ks:// 스키마 리졸버가 있으면 등록. */
    if (host->scheme_resolver) {
        WebKitWebContext *wctx = webkit_web_view_get_context(view);
        webkit_web_context_register_uri_scheme(
            wctx, "ks", on_kb_scheme_request, host, NULL);
    }

    if (host->on_activate) {
        host->on_activate(host->on_activate_ctx);
    }
}

/* -- 공개 API ---------------------------------------------------- */

KSGtkHost *ks_gtk_host_new(const char *app_id,
                           const char *title,
                           int width,
                           int height)
{
    KSGtkHost *h = g_new0(KSGtkHost, 1);
    h->app_id = dup_string(app_id ? app_id : "app.kalsae.unknown");
    h->title  = dup_string(title ? title : "Kalsae");
    h->width  = width  > 0 ? width  : 1024;
    h->height = height > 0 ? height : 768;
    h->pending_scripts = g_ptr_array_new_with_free_func(g_free);

    h->app = gtk_application_new(h->app_id, G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(h->app, "activate",
                     G_CALLBACK(on_app_activate), h);
    return h;
}

void ks_gtk_host_free(KSGtkHost *host)
{
    if (!host) return;
    if (host->app) g_object_unref(host->app);
    if (host->pending_scripts) g_ptr_array_free(host->pending_scripts, TRUE);
    clear_string(&host->app_id);
    clear_string(&host->title);
    clear_string(&host->response_csp);
    g_free(host);
}

void ks_gtk_host_set_message_handler(KSGtkHost *host,
                                     KSGtkMessageFn cb,
                                     void *ctx)
{
    if (!host) return;
    host->on_message = cb;
    host->on_message_ctx = ctx;
}

void ks_gtk_host_set_on_activate(KSGtkHost *host,
                                 KSGtkActivateFn cb,
                                 void *ctx)
{
    if (!host) return;
    host->on_activate = cb;
    host->on_activate_ctx = ctx;
}

void ks_gtk_host_add_user_script(KSGtkHost *host, const char *source)
{
    if (!host || !source) return;
    g_ptr_array_add(host->pending_scripts, g_strdup(source));
}

void ks_gtk_host_load_uri(KSGtkHost *host, const char *uri)
{
    if (!host || !host->web_view || !uri) return;
    webkit_web_view_load_uri(host->web_view, uri);
}

static void eval_js_ready(GObject *source, GAsyncResult *res, gpointer data)
{
    (void) data;
    GError *err = NULL;
    JSCValue *v = webkit_web_view_evaluate_javascript_finish(
        WEBKIT_WEB_VIEW(source), res, &err);
    if (err) {
        fprintf(stderr, "[kb] evaluate_javascript failed: %s\n",
                err->message);
        g_error_free(err);
    }
    if (v) g_object_unref(v);
}

void ks_gtk_host_eval_js(KSGtkHost *host, const char *script)
{
    if (!host || !host->web_view || !script) return;
    webkit_web_view_evaluate_javascript(
        host->web_view,
        script,
        -1,        /* length: NUL 종료 문자열              */
        NULL,      /* world_name: 메인 월드                 */
        NULL,      /* source_uri                            */
        NULL,      /* cancellable                           */
        eval_js_ready,
        NULL);
}

void ks_gtk_host_open_devtools(KSGtkHost *host)
{
    if (!host || !host->web_view) return;
    WebKitSettings *s = webkit_web_view_get_settings(host->web_view);
    webkit_settings_set_enable_developer_extras(s, TRUE);
}

int ks_gtk_host_run(KSGtkHost *host, int argc, char **argv)
{
    if (!host || !host->app) return 1;
    return g_application_run(G_APPLICATION(host->app), argc, argv);
}

typedef struct {
    GApplication *app;
} KSGtkQuitJob;

static gboolean ks_gtk_quit_trampoline(gpointer user_data)
{
    KSGtkQuitJob *job = (KSGtkQuitJob *) user_data;
    if (job && job->app) {
        g_application_quit(job->app);
    }
    g_free(job);
    return G_SOURCE_REMOVE;
}

void ks_gtk_host_quit(KSGtkHost *host)
{
    if (!host || !host->app) return;
    KSGtkQuitJob *job = g_new0(KSGtkQuitJob, 1);
    job->app = G_APPLICATION(host->app);
    g_idle_add(ks_gtk_quit_trampoline, job);
}

/* -- 스레드 간 디스패치 ----------------------------------------- */

typedef struct {
    void (*fn)(void *);
    void *ctx;
} KSGtkIdleJob;

static gboolean ks_gtk_idle_trampoline(gpointer user_data)
{
    KSGtkIdleJob *job = (KSGtkIdleJob *) user_data;
    if (job && job->fn) job->fn(job->ctx);
    g_free(job);
    return G_SOURCE_REMOVE;
}

void ks_gtk_post_main_thread(void (*fn)(void *ctx), void *ctx)
{
    KSGtkIdleJob *job = g_new0(KSGtkIdleJob, 1);
    job->fn = fn;
    job->ctx = ctx;
    g_idle_add(ks_gtk_idle_trampoline, job);
}


/* -- ks:// 스키마 리졸버 ---------------------------------------- */

void ks_gtk_host_set_scheme_resolver(KSGtkHost *host,
                                     KSGtkSchemeResolverFn cb,
                                     void *ctx)
{
    if (!host) return;
    host->scheme_resolver     = cb;
    host->scheme_resolver_ctx = ctx;
}

/* `ks://...` 요청마다 WebKit이 호출하는 핸들러. Swift 쪽
 * 리졸버를 호출해 얻은 바이트를 메모리 입력 스트림으로 감싸
 * 호출자가 제공한 MIME 타입(없으면 octet-stream)으로 응답한다.
 * 리졸버 실패 시 404. */
static void on_kb_scheme_request(WebKitURISchemeRequest *req,
                                 gpointer user_data)
{
    KSGtkHost *host = (KSGtkHost *) user_data;
    if (!host || !host->scheme_resolver) {
        GError *e = g_error_new_literal(
            g_quark_from_static_string("Kalsae"), 404,
            "no scheme resolver");
        webkit_uri_scheme_request_finish_error(req, e);
        g_error_free(e);
        return;
    }

    const char *path = webkit_uri_scheme_request_get_path(req);

    char  *data = NULL;
    size_t len  = 0;
    char  *mime = NULL;
    int rc = host->scheme_resolver(
        path ? path : "/", host->scheme_resolver_ctx,
        &data, &len, &mime);
    if (rc != 0 || !data) {
        GError *e = g_error_new(
            g_quark_from_static_string("Kalsae"), 404,
            "resolver failed for %s", path ? path : "(null)");
        webkit_uri_scheme_request_finish_error(req, e);
        g_error_free(e);
        if (mime) g_free(mime);
        return;
    }

    GInputStream *stream = g_memory_input_stream_new_from_data(
        data, (gssize) len, g_free);

    /* CSP가 있을 때는 응답 헤더를 붙일 수 있도록 완전한
     * WebKitURISchemeResponse를 구성한다. 해당 API가 없는 구버전은
     * `webkit_uri_scheme_request_finish`로 폴백하지만, 이 파일은
     * WebKitGTK 6.0 (2.40+)을 대상으로 하므로 항상 응답 API가
     * 노출되어 있다. */
    WebKitURISchemeResponse *resp =
        webkit_uri_scheme_response_new(stream, (gint64) len);
    webkit_uri_scheme_response_set_content_type(
        resp, mime ? mime : "application/octet-stream");
    webkit_uri_scheme_response_set_status(resp, 200, NULL);
    if (host->response_csp && host->response_csp[0] != '\0') {
        SoupMessageHeaders *hdrs = soup_message_headers_new(
            SOUP_MESSAGE_HEADERS_RESPONSE);
        soup_message_headers_append(
            hdrs, "Content-Security-Policy", host->response_csp);
        webkit_uri_scheme_response_set_http_headers(resp, hdrs);
        /* WebKit이 참조를 취하므로 우리 참조는 해제한다. */
        soup_message_headers_unref(hdrs);
    }
    webkit_uri_scheme_request_finish_with_response(req, resp);
    g_object_unref(resp);
    g_object_unref(stream);
    if (mime) g_free(mime);
}

void ks_gtk_host_set_response_csp(KSGtkHost *host, const char *csp)
{
    if (!host) return;
    clear_string(&host->response_csp);
    if (csp && csp[0] != '\0') {
        host->response_csp = g_strdup(csp);
    }
}
