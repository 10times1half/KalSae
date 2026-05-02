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
#include <unistd.h>
#include <glib.h>
#include <gio/gio.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#if defined(__has_include)
#  if __has_include(<gdk/x11/gdkx.h>)
#    include <gdk/x11/gdkx.h>
#    define KS_GTK_HAS_X11 1
#  endif
#endif

#ifndef KS_GTK_HAS_X11
#define KS_GTK_HAS_X11 0
#endif

static GdkSurface *ks_gtk_window_surface(GtkWindow *window)
{
    if (!window) return NULL;
    if (!GTK_IS_NATIVE(window)) return NULL;
    return gtk_native_get_surface(GTK_NATIVE(window));
}

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

    /* close-request 인터셉터 플래그: 1=활성, 0=비활성. */
    int                   close_interceptor;

    /* Swift-side close handler (우선순위: close_interceptor보다 높음). */
    KSGtkCloseHandlerFn  close_handler;
    void                *close_handler_ctx;

    /* D-Bus logind power callbacks (suspend / resume). */
    KSGtkPowerFn  on_suspend;
    void         *on_suspend_ctx;
    KSGtkPowerFn  on_resume;
    void         *on_resume_ctx;
    guint         dbus_signal_id;   /* g_dbus_connection_signal_subscribe handle */
    GDBusConnection *dbus_conn;     /* system bus connection (weak, unowned) */

    /* Menu state. */
    KSGtkMenuActivateFn  menu_activate_cb;
    void                *menu_activate_ctx;
    GSimpleActionGroup  *menu_actions;   /* owned; installed on window */
    GtkWidget           *menu_bar;       /* GtkPopoverMenuBar child, or NULL */
    GtkWidget           *menu_vbox;      /* vertical GtkBox wrapping menu+webview, or NULL */

    /* 윈도우 상태 영속화. */
    int                   has_pending_restore;     /* 1 = 아래 필드들이 유효 */
    int                   pending_restore_x;
    int                   pending_restore_y;
    int                   pending_restore_w;
    int                   pending_restore_h;
    int                   pending_restore_has_position;
    int                   pending_restore_maximized;
    int                   pending_restore_fullscreen;
    KSGtkStateSaveFn      state_save_handler;
    void                 *state_save_ctx;

    /* 키보드 가속기 (window-scoped). */
    GtkShortcutController *shortcut_controller;  /* owned, attached to window */
    GHashTable            *shortcuts_by_id;      /* (gchar*) id -> KSGtkAccelEntry* */
};

/* 단축키 엔트리 — 등록 해제를 위해 GtkShortcut과 트램폴린 컨텍스트를 보관. */
typedef struct KSGtkAccelEntry {
    GtkShortcut         *shortcut;   /* owned ref */
    KSGtkAcceleratorFn   cb;
    void                *ctx;
} KSGtkAccelEntry;

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

/* -- 전방 선언 ---------------------------------------------------- */
static void on_kb_scheme_request(WebKitURISchemeRequest *req,
                                 gpointer user_data);
/* close-request 핸들러 전방 선언 */

/* close-request 핸들러: 인터셉터가 켜진 경우 창을 닫지 않고
 * JS beforeClose 이벤트를 발사한다. */
static gboolean on_close_request(GtkWindow *win, gpointer user_data)
{
    (void) win;
    KSGtkHost *host = (KSGtkHost *) user_data;
    if (!host) return FALSE;

    /* 닫기가 실제로 진행되든 막히든 관계없이 마지막 윈도우 상태를
     * Swift 측에 흘려보낸다 — 닫히지 않더라도 사용자가 의도한
     * 마지막 상태를 보존하기 위함이다. */
    if (host->state_save_handler) {
        int x = 0, y = 0, w = 0, h = 0;
        int has_pos = 0, maximized = 0, fullscreen = 0;
        if (ks_gtk_host_get_window_state(
                host, &x, &y, &w, &h,
                &has_pos, &maximized, &fullscreen)) {
            host->state_save_handler(x, y, w, h,
                                     has_pos, maximized, fullscreen,
                                     host->state_save_ctx);
        }
    }

    /* Swift-side native 핸들러가 우선. 핸들러가 1을 돌려주면
     * JS beforeClose를 발사하고 닫기를 억제한다. */
    if (host->close_handler) {
        int prevent = host->close_handler(host->close_handler_ctx);
        if (prevent) {
            ks_gtk_host_eval_js(host,
                "if(window.__KS_)window.__KS_.emit('__ks.window.beforeClose',null);");
            return TRUE;
        }
        return FALSE;
    }

    /* 기존 JS-only 인터셉터. */
    if (host->close_interceptor) {
        ks_gtk_host_eval_js(host,
            "if(window.__KS_)window.__KS_.emit('__ks.window.beforeClose',null);");
        return TRUE;  /* 기본 닫기 억제 */
    }
    return FALSE;     /* 기본 닫기 허용 */
}

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

    /* 영속화된 윈도우 상태 복원: 크기/최대화/전체화면은 모든 환경에서
     * 적용하고, 위치는 X11에서만 시도한다(Wayland는 컴포지터가 통제). */
    if (host->has_pending_restore) {
        if (host->pending_restore_w > 0 && host->pending_restore_h > 0) {
            gtk_window_set_default_size(win,
                host->pending_restore_w, host->pending_restore_h);
        }
        if (host->pending_restore_has_position) {
            /* GTK4 does not provide a portable absolute-position API.
             * Keep persisted coordinates for state save, but do not force-move. */
            (void) host->pending_restore_x;
            (void) host->pending_restore_y;
        }
        if (host->pending_restore_maximized) {
            gtk_window_maximize(win);
        }
        if (host->pending_restore_fullscreen) {
            gtk_window_fullscreen(win);
        }
        host->has_pending_restore = 0;
    }

    /* 윈도우 범위 단축키 컨트롤러 부착(처음 한 번). */
    if (!host->shortcut_controller) {
        GtkShortcutController *sc = GTK_SHORTCUT_CONTROLLER(
            gtk_shortcut_controller_new());
        gtk_shortcut_controller_set_scope(
            sc, GTK_SHORTCUT_SCOPE_LOCAL);
        gtk_widget_add_controller(GTK_WIDGET(win),
                                   GTK_EVENT_CONTROLLER(sc));
        host->shortcut_controller = sc;  /* owned by widget; not unref'd */
    }

    /* 웹 컨텍스트에 ks:// 스키마 리졸버가 있으면 등록. */
    if (host->scheme_resolver) {
        WebKitWebContext *wctx = webkit_web_view_get_context(view);
        webkit_web_context_register_uri_scheme(
            wctx, "ks", on_kb_scheme_request, host, NULL);
    }

    /* close-request 시그널을 1회 연결해 인터셉터 플래그로 제어한다. */
    g_signal_connect(win, "close-request",
                     G_CALLBACK(on_close_request), host);

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
    /* Clean up D-Bus power monitor if installed. */
    if (host->dbus_signal_id != 0 && host->dbus_conn) {
        g_dbus_connection_signal_unsubscribe(host->dbus_conn,
                                              host->dbus_signal_id);
        g_object_unref(host->dbus_conn);
        host->dbus_conn = NULL;
        host->dbus_signal_id = 0;
    }
    /* shortcut entries는 hash table free 함수가 ref를 정리한다. */
    if (host->shortcuts_by_id) {
        g_hash_table_destroy(host->shortcuts_by_id);
        host->shortcuts_by_id = NULL;
    }
    /* shortcut_controller는 윈도우 위젯 트리에 의해 소유된다 — 별도 unref 없음. */
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

void ks_gtk_host_set_title(KSGtkHost *host, const char *title)
{
    if (!host) return;
    clear_string(&host->title);
    host->title = dup_string(title ? title : "Kalsae");
    if (host->window) {
        gtk_window_set_title(host->window, host->title);
    }
}

void ks_gtk_host_set_size(KSGtkHost *host, int width, int height)
{
    if (!host) return;
    host->width = width > 0 ? width : host->width;
    host->height = height > 0 ? height : host->height;
    if (host->window) {
        gtk_window_set_default_size(host->window, host->width, host->height);
    }
}

void ks_gtk_host_show(KSGtkHost *host)
{
    if (!host || !host->window) return;
    gtk_widget_set_visible(GTK_WIDGET(host->window), TRUE);
    gtk_window_present(host->window);
}

void ks_gtk_host_hide(KSGtkHost *host)
{
    if (!host || !host->window) return;
    gtk_widget_set_visible(GTK_WIDGET(host->window), FALSE);
}

void ks_gtk_host_focus(KSGtkHost *host)
{
    if (!host || !host->window) return;
    gtk_window_present(host->window);
}

void ks_gtk_host_reload(KSGtkHost *host)
{
    if (!host || !host->web_view) return;
    webkit_web_view_reload(host->web_view);
}

void ks_gtk_host_minimize(KSGtkHost *host)
{
    if (!host || !host->window) return;
    gtk_window_minimize(host->window);
}

void ks_gtk_host_maximize(KSGtkHost *host)
{
    if (!host || !host->window) return;
    gtk_window_maximize(host->window);
}

void ks_gtk_host_unmaximize(KSGtkHost *host)
{
    if (!host || !host->window) return;
    gtk_window_unmaximize(host->window);
}

int ks_gtk_host_is_maximized(KSGtkHost *host)
{
    if (!host || !host->window) return 0;
    return gtk_window_is_maximized(host->window) ? 1 : 0;
}

int ks_gtk_host_is_minimized(KSGtkHost *host)
{
    if (!host || !host->window) return 0;

    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(host->window));
    if (!surface || !GDK_IS_TOPLEVEL(surface)) return 0;

    GdkToplevelState state = gdk_toplevel_get_state(GDK_TOPLEVEL(surface));
    return (state & GDK_TOPLEVEL_STATE_MINIMIZED) ? 1 : 0;
}

void ks_gtk_host_fullscreen(KSGtkHost *host)
{
    if (!host || !host->window) return;
    gtk_window_fullscreen(host->window);
}

void ks_gtk_host_unfullscreen(KSGtkHost *host)
{
    if (!host || !host->window) return;
    gtk_window_unfullscreen(host->window);
}

int ks_gtk_host_is_fullscreen(KSGtkHost *host)
{
    if (!host || !host->window) return 0;
    return gtk_window_is_fullscreen(host->window) ? 1 : 0;
}

int ks_gtk_host_get_size(KSGtkHost *host, int *out_width, int *out_height)
{
    if (!host || !host->window || !out_width || !out_height) return 0;
    GtkWidget *widget = GTK_WIDGET(host->window);
    int width = gtk_widget_get_width(widget);
    int height = gtk_widget_get_height(widget);
    if (width <= 0 || height <= 0) {
        return 0;
    }
    *out_width = width;
    *out_height = height;
    return 1;
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
    {
        SoupMessageHeaders *hdrs = soup_message_headers_new(
            SOUP_MESSAGE_HEADERS_RESPONSE);
        if (host->response_csp && host->response_csp[0] != '\0') {
            soup_message_headers_append(
                hdrs, "Content-Security-Policy", host->response_csp);
        }
        soup_message_headers_append(
            hdrs, "X-Content-Type-Options", "nosniff");
        soup_message_headers_append(
            hdrs, "Referrer-Policy", "no-referrer");
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

/* ================================================================
 * 클립보드
 * ================================================================ */

static GdkClipboard *get_clipboard(KSGtkHost *host)
{
    if (!host || !host->window) return NULL;
    GdkDisplay *display = gtk_widget_get_display(GTK_WIDGET(host->window));
    if (!display) return NULL;
    return gdk_display_get_clipboard(display);
}

void ks_gtk_clipboard_write_text(KSGtkHost *host, const char *text)
{
    GdkClipboard *cb = get_clipboard(host);
    if (!cb || !text) return;
    gdk_clipboard_set_text(cb, text);
}

void ks_gtk_clipboard_clear(KSGtkHost *host)
{
    GdkClipboard *cb = get_clipboard(host);
    if (!cb) return;
    /* GDK4에는 전용 clear API가 없으므로 빈 텍스트로 대체한다. */
    gdk_clipboard_set_text(cb, "");
}

typedef struct {
    KSGtkClipboardTextFn cb;
    void                *ctx;
} ClipReadCtx;

static void on_clipboard_read_finish(GObject *source,
                                     GAsyncResult *result,
                                     gpointer user_data)
{
    ClipReadCtx *rd  = (ClipReadCtx *) user_data;
    GError      *err = NULL;
    char        *text = gdk_clipboard_read_text_finish(
        GDK_CLIPBOARD(source), result, &err);
    rd->cb(text, rd->ctx);
    if (text) g_free(text);
    if (err)  g_error_free(err);
    g_free(rd);
}

void ks_gtk_clipboard_read_text(KSGtkHost *host,
                                KSGtkClipboardTextFn cb,
                                void *ctx)
{
    GdkClipboard *clipboard = get_clipboard(host);
    if (!clipboard) { cb(NULL, ctx); return; }
    ClipReadCtx *rd = g_new0(ClipReadCtx, 1);
    rd->cb  = cb;
    rd->ctx = ctx;
    gdk_clipboard_read_text_async(clipboard, NULL,
                                  on_clipboard_read_finish, rd);
}

int ks_gtk_clipboard_has_text(KSGtkHost *host)
{
    GdkClipboard *clipboard = get_clipboard(host);
    if (!clipboard) return 0;
    GdkContentFormats *formats = gdk_clipboard_get_formats(clipboard);
    return gdk_content_formats_contain_gtype(formats, G_TYPE_STRING) ? 1 : 0;
}

/* ================================================================
 * 클립보드 이미지 (GdkTexture PNG)
 * ================================================================ */

int ks_gtk_clipboard_write_png(KSGtkHost *host,
                                const uint8_t *png_bytes,
                                size_t png_len)
{
    GdkClipboard *clipboard = get_clipboard(host);
    if (!clipboard || !png_bytes || png_len == 0) return 0;

    GBytes *bytes = g_bytes_new(png_bytes, png_len);
    GdkTexture *tex = gdk_texture_new_from_bytes(bytes, NULL);
    g_bytes_unref(bytes);
    if (!tex) return 0;

    gdk_clipboard_set_texture(clipboard, tex);
    g_object_unref(tex);
    return 1;
}

typedef struct {
    KSGtkClipboardImageFn cb;
    void                 *ctx;
} ClipImageReadCtx;

static void on_read_texture_finish(GObject *source,
                                    GAsyncResult *result,
                                    gpointer user_data)
{
    ClipImageReadCtx *rd  = (ClipImageReadCtx *) user_data;
    GError           *err = NULL;
    GdkTexture *tex = gdk_clipboard_read_texture_finish(
        GDK_CLIPBOARD(source), result, &err);

    if (!tex) {
        if (err) g_error_free(err);
        rd->cb(NULL, 0, rd->ctx);
        g_free(rd);
        return;
    }

    GBytes *bytes = gdk_texture_save_to_png_bytes(tex);
    g_object_unref(tex);

    if (!bytes) {
        rd->cb(NULL, 0, rd->ctx);
        g_free(rd);
        return;
    }

    gsize len = 0;
    const guint8 *data = (const guint8 *) g_bytes_get_data(bytes, &len);
    rd->cb(data, (size_t) len, rd->ctx);
    g_bytes_unref(bytes);
    g_free(rd);
}

void ks_gtk_clipboard_read_png(KSGtkHost *host,
                                KSGtkClipboardImageFn cb,
                                void *ctx)
{
    GdkClipboard *clipboard = get_clipboard(host);
    if (!clipboard) { cb(NULL, 0, ctx); return; }

    ClipImageReadCtx *rd = g_new0(ClipImageReadCtx, 1);
    rd->cb  = cb;
    rd->ctx = ctx;
    gdk_clipboard_read_texture_async(clipboard, NULL,
                                      on_read_texture_finish, rd);
}

int ks_gtk_clipboard_has_image(KSGtkHost *host)
{
    GdkClipboard *clipboard = get_clipboard(host);
    if (!clipboard) return 0;
    GdkContentFormats *formats = gdk_clipboard_get_formats(clipboard);
    return gdk_content_formats_contain_gtype(formats, GDK_TYPE_TEXTURE) ? 1 : 0;
}

/* ================================================================
 * 다이얼로그 헬퍼
 * ================================================================ */

/* 필터 배열을 GtkFileChooser에 추가한다. */
static void apply_filters(GtkFileChooser *chooser,
                          const char *const *names,
                          const char *const *globs,
                          int count)
{
    for (int i = 0; i < count; i++) {
        GtkFileFilter *f = gtk_file_filter_new();
        if (names && names[i] && names[i][0])
            gtk_file_filter_set_name(f, names[i]);
        if (globs && globs[i]) {
            /* 세미콜론으로 분리된 glob 목록을 파싱한다. */
            char *copy = g_strdup(globs[i]);
            char *tok  = strtok(copy, ";");
            while (tok) {
                gtk_file_filter_add_pattern(f, tok);
                tok = strtok(NULL, ";");
            }
            g_free(copy);
        }
        gtk_file_chooser_add_filter(chooser, f);
    }
}

/* ================================================================
 * 파일 열기 다이얼로그
 * ================================================================ */

typedef struct {
    KSGtkFilesResultFn cb;
    void              *ctx;
} OpenFilesCtx;

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

static void on_open_files_response(GtkNativeDialog *dlg,
                                   gint             response,
                                   gpointer         user_data)
{
    OpenFilesCtx *oc = (OpenFilesCtx *) user_data;
    if (response == GTK_RESPONSE_ACCEPT) {
        GListModel *files =
            gtk_file_chooser_get_files(GTK_FILE_CHOOSER(dlg));
        guint n = g_list_model_get_n_items(files);
        const char **paths = g_new0(const char *, n + 1);
        for (guint i = 0; i < n; i++) {
            GFile *f = G_FILE(g_list_model_get_item(files, i));
            paths[i] = g_file_get_path(f);
            g_object_unref(f);
        }
        paths[n] = NULL;
        oc->cb(paths, oc->ctx);
        for (guint i = 0; i < n; i++) g_free((gpointer) paths[i]);
        g_free(paths);
        g_object_unref(files);
    } else {
        oc->cb(NULL, oc->ctx);
    }
    g_object_unref(dlg);
    g_free(oc);
}

void ks_gtk_dialog_open_files(KSGtkHost *host,
                              const char *title,
                              const char *default_dir,
                              const char *const *filter_names,
                              const char *const *filter_globs,
                              int filter_count,
                              int allow_multiple,
                              KSGtkFilesResultFn cb, void *ctx)
{
    GtkFileChooserNative *dlg = gtk_file_chooser_native_new(
        title ? title : "Open",
        host ? GTK_WINDOW(host->window) : NULL,
        GTK_FILE_CHOOSER_ACTION_OPEN,
        "_Open", "_Cancel");
    gtk_file_chooser_set_select_multiple(GTK_FILE_CHOOSER(dlg),
                                         allow_multiple ? TRUE : FALSE);
    if (default_dir && default_dir[0]) {
        GFile *dir = g_file_new_for_path(default_dir);
        gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(dlg),
                                            dir, NULL);
        g_object_unref(dir);
    }
    apply_filters(GTK_FILE_CHOOSER(dlg),
                  filter_names, filter_globs, filter_count);

    OpenFilesCtx *oc = g_new0(OpenFilesCtx, 1);
    oc->cb  = cb;
    oc->ctx = ctx;
    g_signal_connect(dlg, "response",
                     G_CALLBACK(on_open_files_response), oc);
    gtk_native_dialog_show(GTK_NATIVE_DIALOG(dlg));
}

/* ================================================================
 * 파일 저장 다이얼로그
 * ================================================================ */

typedef struct {
    KSGtkFileResultFn cb;
    void             *ctx;
} SaveFileCtx;

static void on_save_file_response(GtkNativeDialog *dlg,
                                  gint             response,
                                  gpointer         user_data)
{
    SaveFileCtx *sc = (SaveFileCtx *) user_data;
    if (response == GTK_RESPONSE_ACCEPT) {
        GFile *f    = gtk_file_chooser_get_file(GTK_FILE_CHOOSER(dlg));
        char  *path = f ? g_file_get_path(f) : NULL;
        sc->cb(path, sc->ctx);
        if (path) g_free(path);
        if (f)    g_object_unref(f);
    } else {
        sc->cb(NULL, sc->ctx);
    }
    g_object_unref(dlg);
    g_free(sc);
}

void ks_gtk_dialog_save_file(KSGtkHost *host,
                             const char *title,
                             const char *default_dir,
                             const char *default_name,
                             const char *const *filter_names,
                             const char *const *filter_globs,
                             int filter_count,
                             KSGtkFileResultFn cb, void *ctx)
{
    GtkFileChooserNative *dlg = gtk_file_chooser_native_new(
        title ? title : "Save",
        host ? GTK_WINDOW(host->window) : NULL,
        GTK_FILE_CHOOSER_ACTION_SAVE,
        "_Save", "_Cancel");
    if (default_dir && default_dir[0]) {
        GFile *dir = g_file_new_for_path(default_dir);
        gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(dlg),
                                            dir, NULL);
        g_object_unref(dir);
    }
    if (default_name && default_name[0])
        gtk_file_chooser_set_current_name(GTK_FILE_CHOOSER(dlg),
                                          default_name);
    apply_filters(GTK_FILE_CHOOSER(dlg),
                  filter_names, filter_globs, filter_count);

    SaveFileCtx *sc = g_new0(SaveFileCtx, 1);
    sc->cb  = cb;
    sc->ctx = ctx;
    g_signal_connect(dlg, "response",
                     G_CALLBACK(on_save_file_response), sc);
    gtk_native_dialog_show(GTK_NATIVE_DIALOG(dlg));
}

/* ================================================================
 * 폴더 선택 다이얼로그
 * ================================================================ */

static void on_select_folder_response(GtkNativeDialog *dlg,
                                      gint             response,
                                      gpointer         user_data)
{
    SaveFileCtx *sc = (SaveFileCtx *) user_data;
    if (response == GTK_RESPONSE_ACCEPT) {
        GFile *f    = gtk_file_chooser_get_file(GTK_FILE_CHOOSER(dlg));
        char  *path = f ? g_file_get_path(f) : NULL;
        sc->cb(path, sc->ctx);
        if (path) g_free(path);
        if (f)    g_object_unref(f);
    } else {
        sc->cb(NULL, sc->ctx);
    }
    g_object_unref(dlg);
    g_free(sc);
}

void ks_gtk_dialog_select_folder(KSGtkHost *host,
                                 const char *title,
                                 const char *default_dir,
                                 KSGtkFileResultFn cb, void *ctx)
{
    GtkFileChooserNative *dlg = gtk_file_chooser_native_new(
        title ? title : "Select Folder",
        host ? GTK_WINDOW(host->window) : NULL,
        GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER,
        "_Open", "_Cancel");
    if (default_dir && default_dir[0]) {
        GFile *dir = g_file_new_for_path(default_dir);
        gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(dlg),
                                            dir, NULL);
        g_object_unref(dir);
    }

    SaveFileCtx *sc = g_new0(SaveFileCtx, 1);
    sc->cb  = cb;
    sc->ctx = ctx;
    g_signal_connect(dlg, "response",
                     G_CALLBACK(on_select_folder_response), sc);
    gtk_native_dialog_show(GTK_NATIVE_DIALOG(dlg));
}

/* ================================================================
 * 메시지 다이얼로그
 * ================================================================ */

typedef struct {
    KSGtkMsgResultFn cb;
    void            *ctx;
    int              buttons; /* 0=ok 1=okCancel 2=yesNo 3=yesNoCancel */
} MsgCtx;

static void on_msg_response(GtkDialog *dlg,
                            gint       response,
                            gpointer   user_data)
{
    MsgCtx *mc = (MsgCtx *) user_data;
    int result;
    switch (response) {
    case GTK_RESPONSE_OK:
    case GTK_RESPONSE_YES:
        result = 0;
        break;
    case GTK_RESPONSE_CANCEL:
    case GTK_RESPONSE_NO:
        result = (mc->buttons == 2 /* yesNo */) ? 1 : 1;
        break;
    case GTK_RESPONSE_DELETE_EVENT:
        result = -1;
        break;
    default:
        result = -1;
        break;
    }
    mc->cb(result, mc->ctx);
    gtk_window_destroy(GTK_WINDOW(dlg));
    g_free(mc);
}

void ks_gtk_dialog_message(KSGtkHost *host,
                           int kind,
                           const char *title,
                           const char *message,
                           const char *detail,
                           int buttons,
                           KSGtkMsgResultFn cb, void *ctx)
{
    GtkMessageType msg_type;
    switch (kind) {
    case 1:  msg_type = GTK_MESSAGE_WARNING; break;
    case 2:  msg_type = GTK_MESSAGE_ERROR;   break;
    case 3:  msg_type = GTK_MESSAGE_QUESTION; break;
    default: msg_type = GTK_MESSAGE_INFO;    break;
    }

    GtkButtonsType btn_type;
    switch (buttons) {
    case 1:  btn_type = GTK_BUTTONS_OK_CANCEL; break;
    case 2:  btn_type = GTK_BUTTONS_YES_NO;    break;
    case 3:  btn_type = GTK_BUTTONS_NONE;      break; /* 수동 추가 */
    default: btn_type = GTK_BUTTONS_OK;        break;
    }

    GtkWidget *dlg = gtk_message_dialog_new(
        host ? GTK_WINDOW(host->window) : NULL,
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        msg_type,
        btn_type,
        "%s", message ? message : "");

    if (title && title[0])
        gtk_window_set_title(GTK_WINDOW(dlg), title);

    if (detail && detail[0])
        gtk_message_dialog_format_secondary_text(
            GTK_MESSAGE_DIALOG(dlg), "%s", detail);

    if (buttons == 3) {
        gtk_dialog_add_button(GTK_DIALOG(dlg), "_Yes",    GTK_RESPONSE_YES);
        gtk_dialog_add_button(GTK_DIALOG(dlg), "_No",     GTK_RESPONSE_NO);
        gtk_dialog_add_button(GTK_DIALOG(dlg), "_Cancel", GTK_RESPONSE_CANCEL);
    }

    MsgCtx *mc = g_new0(MsgCtx, 1);
    mc->cb      = cb;
    mc->ctx     = ctx;
    mc->buttons = buttons;
    g_signal_connect(dlg, "response", G_CALLBACK(on_msg_response), mc);
    gtk_widget_show(dlg);
}

#pragma GCC diagnostic pop

/* ================================================================
 * 고급 WebView / 윈도우 제어 (Phase 4)
 * ================================================================ */

void ks_gtk_host_set_zoom_level(KSGtkHost *host, double level)
{
    if (!host || !host->web_view) return;
    webkit_web_view_set_zoom_level(host->web_view, level);
}

double ks_gtk_host_get_zoom_level(KSGtkHost *host)
{
    if (!host || !host->web_view) return 1.0;
    return webkit_web_view_get_zoom_level(host->web_view);
}

void ks_gtk_host_set_background_color(KSGtkHost *host,
                                      float r, float g_ch,
                                      float b, float a)
{
    if (!host || !host->web_view) return;
    GdkRGBA rgba = { r, g_ch, b, a };
    webkit_web_view_set_background_color(host->web_view, &rgba);
}

void ks_gtk_host_set_theme(KSGtkHost *host, int theme)
{
    (void) host;
    /* theme: 0=system/default, 1=light, 2=dark */
    GtkSettings *settings = gtk_settings_get_default();
    if (!settings) return;
    /* dark=2 → prefer-dark-theme TRUE; light/system → FALSE.
     * A full system-aware implementation would query GdkMonitor's
     * color-scheme property; this covers the common use-case. */
    gboolean dark = (theme == 2) ? TRUE : FALSE;
    g_object_set(settings, "gtk-application-prefer-dark-theme", dark, NULL);
}

void ks_gtk_host_set_min_size(KSGtkHost *host, int width, int height)
{
    if (!host || !host->window) return;
    gtk_widget_set_size_request(GTK_WIDGET(host->window), width, height);
}

void ks_gtk_host_set_max_size(KSGtkHost *host, int width, int height)
{
    if (!host || !host->window) return;
    /* GTK4 has no stable cross-backend max-size setter for toplevels.
     * Record the intended caps and best-effort clamp current default size. */
    host->width  = width  > 0 ? width  : host->width;
    host->height = height > 0 ? height : host->height;

    int cur_w = 0;
    int cur_h = 0;
    gtk_window_get_default_size(host->window, &cur_w, &cur_h);

    if (width > 0 && (cur_w <= 0 || cur_w > width)) cur_w = width;
    if (height > 0 && (cur_h <= 0 || cur_h > height)) cur_h = height;
    if (cur_w > 0 && cur_h > 0) {
        gtk_window_set_default_size(host->window, cur_w, cur_h);
    }
}

void ks_gtk_host_set_position(KSGtkHost *host, int x, int y)
{
    if (!host || !host->window) return;
    GdkSurface *surface = ks_gtk_window_surface(host->window);
    if (!surface) return;
    /* GTK4 does not expose a stable explicit move API for toplevel windows. */
    (void) surface;
    (void) x;
    (void) y;
}

int ks_gtk_host_get_position(KSGtkHost *host, int *out_x, int *out_y)
{
    if (!host || !host->window || !out_x || !out_y) return 0;
    GdkSurface *surface = ks_gtk_window_surface(host->window);
    if (!surface) return 0;
#if KS_GTK_HAS_X11
    if (GDK_IS_X11_SURFACE(surface)) {
        *out_x = gdk_x11_surface_get_x(surface);
        *out_y = gdk_x11_surface_get_y(surface);
        return 1;
    }
#endif
    return 0;
}

void ks_gtk_host_center(KSGtkHost *host)
{
    if (!host || !host->window) return;
    GdkDisplay *display = gtk_widget_get_display(GTK_WIDGET(host->window));
    if (!display) return;
    GdkSurface *surface = ks_gtk_window_surface(host->window);
    if (!surface) return;
    /* Use primary monitor geometry if available. */
    GdkMonitor *monitor = gdk_display_get_primary_monitor(display);
    if (!monitor) {
        /* Fall back to the monitor nearest the current window. */
        GListModel *monitors = gdk_display_get_monitors(display);
        if (monitors && g_list_model_get_n_items(monitors) > 0)
            monitor = GDK_MONITOR(g_list_model_get_item(monitors, 0));
    }
    if (!monitor) return;
    GdkRectangle work_area;
    gdk_monitor_get_geometry(monitor, &work_area);
    GtkWidget *widget = GTK_WIDGET(host->window);
    int win_w = gtk_widget_get_width(widget);
    int win_h = gtk_widget_get_height(widget);
    if (win_w <= 0) win_w = host->width;
    if (win_h <= 0) win_h = host->height;
    int cx = work_area.x + (work_area.width  - win_w) / 2;
    int cy = work_area.y + (work_area.height - win_h) / 2;
    ks_gtk_host_set_position(host, cx, cy);
}

void ks_gtk_host_set_close_interceptor(KSGtkHost *host, int enabled)
{
    if (!host) return;
    host->close_interceptor = enabled ? 1 : 0;
}

void ks_gtk_host_set_close_handler(KSGtkHost *host,
                                    KSGtkCloseHandlerFn cb,
                                    void *ctx)
{
    if (!host) return;
    host->close_handler     = cb;
    host->close_handler_ctx = ctx;
}

void ks_gtk_host_set_keep_above(KSGtkHost *host, int enabled)
{
    if (!host || !host->window) return;
    gtk_window_set_keep_above(host->window, enabled ? TRUE : FALSE);
}

/* ----------------------------------------------------------------
 * 윈도우 상태 영속화 (window state persistence)
 * ---------------------------------------------------------------- */

void ks_gtk_host_set_pending_restore_state(KSGtkHost *host,
                                            int x, int y,
                                            int width, int height,
                                            int has_position,
                                            int maximized,
                                            int fullscreen)
{
    if (!host) return;
    host->has_pending_restore         = 1;
    host->pending_restore_x           = x;
    host->pending_restore_y           = y;
    host->pending_restore_w           = width;
    host->pending_restore_h           = height;
    host->pending_restore_has_position = has_position ? 1 : 0;
    host->pending_restore_maximized   = maximized ? 1 : 0;
    host->pending_restore_fullscreen  = fullscreen ? 1 : 0;
}

int ks_gtk_host_get_window_state(KSGtkHost *host,
                                  int *out_x, int *out_y,
                                  int *out_width, int *out_height,
                                  int *out_has_position,
                                  int *out_maximized,
                                  int *out_fullscreen)
{
    if (!host || !host->window) return 0;

    int w = 0, h = 0;
    if (out_width || out_height) {
        gtk_window_get_default_size(host->window, &w, &h);
    }
    /* gtk_window_get_default_size는 윈도우가 매핑된 후에는 마지막
     * 사용자 크기를 반영하지 않을 수 있으므로 위젯 할당 크기로 폴백한다. */
    if (w <= 0 || h <= 0) {
        GtkWidget *wid = GTK_WIDGET(host->window);
        int aw = gtk_widget_get_width(wid);
        int ah = gtk_widget_get_height(wid);
        if (aw > 0) w = aw;
        if (ah > 0) h = ah;
    }
    if (out_width)  *out_width  = w;
    if (out_height) *out_height = h;

    int has_pos = 0, x = 0, y = 0;
    GdkSurface *surf = ks_gtk_window_surface(host->window);
#if KS_GTK_HAS_X11
    if (surf && GDK_IS_X11_SURFACE(surf)) {
        /* GTK4는 X11에서만 신뢰할 수 있는 위치를 노출. */
        x = gdk_x11_surface_get_x(surf);
        y = gdk_x11_surface_get_y(surf);
        has_pos = 1;
    }
#endif
    if (out_x) *out_x = x;
    if (out_y) *out_y = y;
    if (out_has_position) *out_has_position = has_pos;

    if (out_maximized) {
        *out_maximized = gtk_window_is_maximized(host->window) ? 1 : 0;
    }
    if (out_fullscreen) {
        *out_fullscreen = gtk_window_is_fullscreen(host->window) ? 1 : 0;
    }
    return 1;
}

void ks_gtk_host_set_state_save_handler(KSGtkHost *host,
                                         KSGtkStateSaveFn cb,
                                         void *ctx)
{
    if (!host) return;
    host->state_save_handler = cb;
    host->state_save_ctx     = ctx;
}

/* ----------------------------------------------------------------
 * 키보드 가속기 (window-scoped)
 * ---------------------------------------------------------------- */

static void ks_gtk_accel_entry_free(gpointer p)
{
    KSGtkAccelEntry *entry = (KSGtkAccelEntry *) p;
    if (!entry) return;
    /* shortcut은 controller가 보유한 ref를 unref하면 정리된다.
     * 우리가 잡고 있던 추가 ref만 해제. */
    if (entry->shortcut) g_object_unref(entry->shortcut);
    g_free(entry);
}

/* GtkShortcutFunc: callback action에서 호출됨. 메인 스레드. */
static gboolean on_shortcut_activate(GtkWidget *widget,
                                      GVariant  *args,
                                      gpointer   user_data)
{
    (void) widget; (void) args;
    KSGtkAccelEntry *entry = (KSGtkAccelEntry *) user_data;
    if (!entry || !entry->cb) return FALSE;
    int rc = entry->cb(entry->ctx);
    return rc ? TRUE : FALSE;
}

int ks_gtk_host_install_accelerator(KSGtkHost *host,
                                     const char *id,
                                     const char *trigger,
                                     KSGtkAcceleratorFn cb,
                                     void *ctx)
{
    if (!host || !id || !trigger || !cb) return 0;
    if (!host->shortcut_controller) {
        /* 윈도우가 아직 활성화되지 않음 — 단축키 등록은 윈도우가
         * 만들어진 후에만 가능하다. 호출자는 start 이후 등록해야 한다. */
        return 0;
    }

    GtkShortcutTrigger *trig = gtk_shortcut_trigger_parse_string(trigger);
    if (!trig) return 0;

    if (!host->shortcuts_by_id) {
        host->shortcuts_by_id = g_hash_table_new_full(
            g_str_hash, g_str_equal, g_free, ks_gtk_accel_entry_free);
    }

    /* 같은 id가 있으면 먼저 제거(해시 테이블 free 함수가 controller에서도 제거해줌은 아님). */
    KSGtkAccelEntry *existing = (KSGtkAccelEntry *)
        g_hash_table_lookup(host->shortcuts_by_id, id);
    if (existing) {
        gtk_shortcut_controller_remove_shortcut(
            host->shortcut_controller, existing->shortcut);
        g_hash_table_remove(host->shortcuts_by_id, id);
    }

    KSGtkAccelEntry *entry = g_new0(KSGtkAccelEntry, 1);
    entry->cb = cb;
    entry->ctx = ctx;

    GtkShortcutAction *action = gtk_callback_action_new(
        on_shortcut_activate, entry, NULL);
    GtkShortcut *shortcut = gtk_shortcut_new(trig, action);
    /* 우리가 entry에 들고 있는 ref를 명시적으로 잡아둔다(controller 추가 시
     * 한 번 ref를 가져가지만 우리가 별도로 보유하면 안전하다). */
    g_object_ref(shortcut);
    entry->shortcut = shortcut;

    gtk_shortcut_controller_add_shortcut(
        host->shortcut_controller, shortcut);

    g_hash_table_replace(host->shortcuts_by_id, g_strdup(id), entry);
    return 1;
}

void ks_gtk_host_uninstall_accelerator(KSGtkHost *host, const char *id)
{
    if (!host || !id || !host->shortcuts_by_id) return;
    KSGtkAccelEntry *entry = (KSGtkAccelEntry *)
        g_hash_table_lookup(host->shortcuts_by_id, id);
    if (!entry) return;
    if (host->shortcut_controller && entry->shortcut) {
        gtk_shortcut_controller_remove_shortcut(
            host->shortcut_controller, entry->shortcut);
    }
    g_hash_table_remove(host->shortcuts_by_id, id);
}

void ks_gtk_host_uninstall_all_accelerators(KSGtkHost *host)
{
    if (!host || !host->shortcuts_by_id) return;
    if (host->shortcut_controller) {
        GHashTableIter it;
        gpointer key, value;
        g_hash_table_iter_init(&it, host->shortcuts_by_id);
        while (g_hash_table_iter_next(&it, &key, &value)) {
            KSGtkAccelEntry *entry = (KSGtkAccelEntry *) value;
            if (entry && entry->shortcut) {
                gtk_shortcut_controller_remove_shortcut(
                    host->shortcut_controller, entry->shortcut);
            }
        }
    }
    g_hash_table_remove_all(host->shortcuts_by_id);
}

/* ----------------------------------------------------------------
 * D-Bus logind PrepareForSleep (suspend / resume)
 * ----------------------------------------------------------------
 * Signal signature: PrepareForSleep(b going_to_sleep)
 *   going_to_sleep = TRUE  → system is about to suspend
 *   going_to_sleep = FALSE → system resumed from suspend
 */

static void on_prepare_for_sleep(GDBusConnection *conn,
                                  const gchar     *sender_name,
                                  const gchar     *object_path,
                                  const gchar     *interface_name,
                                  const gchar     *signal_name,
                                  GVariant        *parameters,
                                  gpointer         user_data)
{
    (void) conn; (void) sender_name; (void) object_path;
    (void) interface_name; (void) signal_name;
    KSGtkHost *host = (KSGtkHost *) user_data;
    if (!host) return;

    gboolean going_to_sleep = FALSE;
    g_variant_get(parameters, "(b)", &going_to_sleep);

    if (going_to_sleep) {
        if (host->on_suspend) host->on_suspend(host->on_suspend_ctx);
    } else {
        if (host->on_resume)  host->on_resume(host->on_resume_ctx);
    }
}

void ks_gtk_host_set_on_suspend(KSGtkHost *host,
                                 KSGtkPowerFn cb,
                                 void *ctx)
{
    if (!host) return;
    host->on_suspend     = cb;
    host->on_suspend_ctx = ctx;
    ks_gtk_host_install_power_monitor(host);
}

void ks_gtk_host_set_on_resume(KSGtkHost *host,
                                KSGtkPowerFn cb,
                                void *ctx)
{
    if (!host) return;
    host->on_resume     = cb;
    host->on_resume_ctx = ctx;
    ks_gtk_host_install_power_monitor(host);
}

void ks_gtk_host_install_power_monitor(KSGtkHost *host)
{
    if (!host) return;
    if (host->dbus_signal_id != 0) return;  /* already installed */
    if (!host->on_suspend && !host->on_resume) return;

    GError *err = NULL;
    GDBusConnection *conn = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &err);
    if (!conn) {
        if (err) {
            fprintf(stderr, "[kalsae] D-Bus system bus unavailable: %s\n",
                    err->message);
            g_error_free(err);
        }
        return;
    }
    host->dbus_conn = conn;
    host->dbus_signal_id = g_dbus_connection_signal_subscribe(
        conn,
        "org.freedesktop.login1",
        "org.freedesktop.login1.Manager",
        "PrepareForSleep",
        "/org/freedesktop/login1",
        NULL,               /* arg0 match */
        G_DBUS_SIGNAL_FLAGS_NONE,
        on_prepare_for_sleep,
        host,
        NULL);
}

void ks_gtk_host_remove_power_monitor(KSGtkHost *host)
{
    if (!host || host->dbus_signal_id == 0) return;
    if (host->dbus_conn) {
        g_dbus_connection_signal_unsubscribe(host->dbus_conn,
                                              host->dbus_signal_id);
        g_object_unref(host->dbus_conn);
        host->dbus_conn = NULL;
    }
    host->dbus_signal_id = 0;
}

/* ----------------------------------------------------------------
 * Print UI
 * ---------------------------------------------------------------- */

void ks_gtk_host_show_print_ui(KSGtkHost *host, int system_dialog)
{
    if (!host || !host->web_view) return;
    WebKitPrintOperation *op = webkit_print_operation_new(host->web_view);
    if (system_dialog) {
        webkit_print_operation_run_dialog(
            op, host->window ? GTK_WINDOW(host->window) : NULL);
    } else {
        webkit_print_operation_print(op);
    }
    g_object_unref(op);
}

/* ----------------------------------------------------------------
 * Capture / Snapshot
 * ---------------------------------------------------------------- */

typedef struct {
    KSGtkSnapshotResultFn cb;
    void                 *ctx;
} KSGtkSnapshotCtx;

static void on_snapshot_done(GObject *source, GAsyncResult *res,
                             gpointer user_data)
{
    KSGtkSnapshotCtx *sc = (KSGtkSnapshotCtx *) user_data;
    GError *err = NULL;

    GdkTexture *tex = webkit_web_view_snapshot_finish(
        WEBKIT_WEB_VIEW(source), res, &err);

    if (err || !tex) {
        if (err) g_error_free(err);
        sc->cb(NULL, 0, sc->ctx);
        g_free(sc);
        return;
    }

    /* GdkTexture → PNG bytes */
    GBytes *bytes = gdk_texture_save_to_png_bytes(tex);
    g_object_unref(tex);

    if (!bytes) {
        sc->cb(NULL, 0, sc->ctx);
        g_free(sc);
        return;
    }

    gsize len = 0;
    const guint8 *data = (const guint8 *) g_bytes_get_data(bytes, &len);
    sc->cb(data, (size_t) len, sc->ctx);

    g_bytes_unref(bytes);
    g_free(sc);
}

void ks_gtk_host_capture_preview(KSGtkHost *host,
                                 int format,
                                 KSGtkSnapshotResultFn cb,
                                 void *ctx)
{
    (void) format; /* JPEG is not yet supported; always produces PNG */
    if (!host || !host->web_view) {
        cb(NULL, 0, ctx);
        return;
    }
    KSGtkSnapshotCtx *sc = g_new0(KSGtkSnapshotCtx, 1);
    sc->cb  = cb;
    sc->ctx = ctx;
    webkit_web_view_snapshot(
        host->web_view,
        WEBKIT_SNAPSHOT_REGION_FULL_DOCUMENT,
        WEBKIT_SNAPSHOT_OPTIONS_NONE,
        NULL,              /* cancellable */
        on_snapshot_done,
        sc);
}

/* ================================================================
 * \uba54\ub274 (GMenuModel + GtkPopoverMenuBar / GtkPopoverMenu)
 * ================================================================ */

/* Per-action context, freed by GObject when the GSimpleAction is unref'd. */
typedef struct {
    KSGtkMenuActivateFn cb;
    void               *ctx;
    char               *action_id;
} MenuActionCtx;

static void on_menu_action_activate(GSimpleAction *action,
                                     GVariant      *parameter,
                                     gpointer       user_data)
{
    (void) action; (void) parameter;
    MenuActionCtx *mac = (MenuActionCtx *) user_data;
    if (mac && mac->cb) mac->cb(mac->action_id, mac->ctx);
}

static void free_menu_action_ctx(gpointer data)
{
    MenuActionCtx *mac = (MenuActionCtx *) data;
    if (mac) { g_free(mac->action_id); g_free(mac); }
}

/* ----------------------------------------------------------------
 * Flat-stream GMenu builder.
 *
 * Stack-based recursive descent over the KSMenuEntry flat array:
 *   kind 0  action
 *   kind 1  separator (appended as section with empty model)
 *   kind 2  submenu_start
 *   kind 3  submenu_end
 *   kind 4  section_start
 *   kind 5  section_end
 *
 * Returns the number of entries consumed (recursive calls consume
 * their own entries from `*pos`).
 * ---------------------------------------------------------------- */
static void build_gmenu(GMenu              *parent,
                         GSimpleActionGroup *group,
                         const char         *prefix,   /* "menu" or "ctx" */
                         const KSMenuEntry  *entries,
                         int                 count,
                         int                *pos,
                         KSGtkMenuActivateFn cb,
                         void               *cb_ctx)
{
    while (*pos < count) {
        const KSMenuEntry *e = &entries[*pos];
        (*pos)++;

        switch (e->kind) {
        case 0: { /* action */
            const char *raw_id = e->action_id ? e->action_id : "";
            /* Build a GAction-safe name by replacing bad chars. */
            char *safe = g_strdup(raw_id);
            for (char *p = safe; *p; p++) {
                if (!g_ascii_isalnum(*p) && *p != '-' && *p != '.') *p = '_';
            }
            /* Avoid duplicate registration. */
            if (!g_action_map_lookup_action(G_ACTION_MAP(group), safe)) {
                GSimpleAction *act = g_simple_action_new(safe, NULL);
                g_simple_action_set_enabled(act,
                    e->enabled ? TRUE : FALSE);
                MenuActionCtx *mac = g_new0(MenuActionCtx, 1);
                mac->cb        = cb;
                mac->ctx       = cb_ctx;
                mac->action_id = g_strdup(raw_id);
                g_signal_connect_data(act, "activate",
                    G_CALLBACK(on_menu_action_activate),
                    mac, (GClosureNotify) free_menu_action_ctx,
                    G_CONNECT_DEFAULT);
                g_action_map_add_action(G_ACTION_MAP(group), G_ACTION(act));
                g_object_unref(act);
            }
            char *full = g_strdup_printf("%s.%s", prefix, safe);
            g_menu_append(parent, e->label ? e->label : "", full);
            g_free(full);
            g_free(safe);
            break;
        }
        case 1: { /* separator — append as an empty section */
            GMenu *sep = g_menu_new();
            g_menu_append_section(parent, NULL, G_MENU_MODEL(sep));
            g_object_unref(sep);
            break;
        }
        case 2: { /* submenu_start */
            GMenu *sub = g_menu_new();
            build_gmenu(sub, group, prefix, entries, count, pos, cb, cb_ctx);
            g_menu_append_submenu(parent,
                e->label ? e->label : "", G_MENU_MODEL(sub));
            g_object_unref(sub);
            break;
        }
        case 3: /* submenu_end — return to caller */
            return;
        case 4: { /* section_start */
            GMenu *sec = g_menu_new();
            build_gmenu(sec, group, prefix, entries, count, pos, cb, cb_ctx);
            g_menu_append_section(parent,
                (e->label && e->label[0]) ? e->label : NULL,
                G_MENU_MODEL(sec));
            g_object_unref(sec);
            break;
        }
        case 5: /* section_end — return to caller */
            return;
        default:
            break;
        }
    }
}

void ks_gtk_host_install_menu(KSGtkHost *host,
                               const KSMenuEntry *entries,
                               int entry_count,
                               KSGtkMenuActivateFn cb,
                               void *ctx)
{
    if (!host || !host->window) return;

    host->menu_activate_cb  = cb;
    host->menu_activate_ctx = ctx;

    /* Remove existing menu bar + wrapping box if present. */
    if (host->menu_bar) {
        /* The vbox owns menu_bar and the webview widget.
         * We need to detach the webview, destroy the vbox, then
         * re-create the structure. */
        GtkWidget *wv = GTK_WIDGET(host->web_view);
        if (wv) g_object_ref(wv);
        if (host->menu_vbox) {
            gtk_window_set_child(host->window, NULL);
            host->menu_bar  = NULL;
            host->menu_vbox = NULL;
        }
        if (host->menu_actions) {
            gtk_widget_remove_action_group(GTK_WIDGET(host->window), "menu");
            g_object_unref(host->menu_actions);
            host->menu_actions = NULL;
        }
        if (wv) g_object_unref(wv);
    } else if (host->menu_actions) {
        gtk_widget_remove_action_group(GTK_WIDGET(host->window), "menu");
        g_object_unref(host->menu_actions);
        host->menu_actions = NULL;
    }

    /* Build new GSimpleActionGroup + GMenu. */
    GSimpleActionGroup *group = g_simple_action_group_new();
    GMenu *model = g_menu_new();
    int pos = 0;
    build_gmenu(model, group, "menu", entries, entry_count, &pos, cb, ctx);

    gtk_widget_insert_action_group(GTK_WIDGET(host->window), "menu",
                                    G_ACTION_GROUP(group));
    host->menu_actions = group; /* transfer ownership */

    /* Create the menu bar widget. */
    GtkWidget *bar = gtk_popover_menu_bar_new_from_model(
        G_MENU_MODEL(model));
    g_object_unref(model);

    /* Wrap existing window child + bar in a vertical box. */
    GtkWidget *current_child = gtk_window_get_child(host->window);
    if (current_child) g_object_ref(current_child);
    gtk_window_set_child(host->window, NULL);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_box_append(GTK_BOX(vbox), bar);
    if (current_child) {
        gtk_widget_set_vexpand(current_child, TRUE);
        gtk_box_append(GTK_BOX(vbox), current_child);
        g_object_unref(current_child);
    }
    gtk_window_set_child(host->window, vbox);
    host->menu_bar  = bar;
    host->menu_vbox = vbox;
}

void ks_gtk_host_show_context_menu(KSGtkHost *host,
                                    const KSMenuEntry *entries,
                                    int entry_count,
                                    int x, int y,
                                    KSGtkMenuActivateFn cb,
                                    void *ctx)
{
    if (!host || !host->window) return;

    GSimpleActionGroup *group = g_simple_action_group_new();
    GMenu *model = g_menu_new();
    int pos = 0;
    build_gmenu(model, group, "ctx", entries, entry_count, &pos, cb, ctx);

    GtkWidget *parent = GTK_WIDGET(host->web_view
                                    ? host->web_view
                                    : host->window);
    gtk_widget_insert_action_group(parent, "ctx", G_ACTION_GROUP(group));
    g_object_unref(group);

    GtkWidget *popover = gtk_popover_menu_new_from_model(G_MENU_MODEL(model));
    g_object_unref(model);
    gtk_widget_set_parent(popover, parent);
    GdkRectangle rect = { x, y, 1, 1 };
    gtk_popover_set_pointing_to(GTK_POPOVER(popover), &rect);
    gtk_popover_set_has_arrow(GTK_POPOVER(popover), FALSE);
    gtk_popover_popup(GTK_POPOVER(popover));
}

/* ================================================================
 * 시스템 트레이 (StatusNotifierItem + DBusMenu)
 * ================================================================
 * 본 구현은 GIO `GDBusConnection`만 사용해 SNI/DBusMenu를 D-Bus
 * 세션 버스에 직접 노출한다. AppIndicator3/libayatana 의존성 없음.
 * 메뉴는 평탄 구조(서브메뉴 미지원, v1 스코프).
 */

#define KS_TRAY_SNI_PATH      "/StatusNotifierItem"
#define KS_TRAY_MENU_PATH     "/MenuBar"
#define KS_TRAY_WATCHER_NAME  "org.kde.StatusNotifierWatcher"
#define KS_TRAY_WATCHER_PATH  "/StatusNotifierWatcher"
#define KS_TRAY_WATCHER_IFACE "org.kde.StatusNotifierWatcher"
#define KS_TRAY_SNI_IFACE     "org.kde.StatusNotifierItem"
#define KS_TRAY_MENU_IFACE    "com.canonical.dbusmenu"

typedef struct KSGtkTrayItem {
    int   id;             /* 0은 root reserved; 항목은 1부터 시작. */
    char *label;          /* 구분선이면 NULL. */
    char *command_id;     /* nullable. */
    int   enabled;        /* 0/1 */
    int   is_separator;   /* 0/1 */
} KSGtkTrayItem;

struct KSGtkTray {
    GDBusConnection      *conn;
    char                 *bus_name;     /* org.kde.StatusNotifierItem-<pid>-<seq> */
    guint                 owner_id;     /* g_bus_own_name id */
    guint                 sni_reg_id;   /* object registration */
    guint                 menu_reg_id;  /* object registration */
    char                 *app_id;
    char                 *icon_path;
    char                 *tooltip;
    KSGtkTrayItem        *items;
    int                   item_count;
    int                   installed;    /* 1 = 등록 성공 */
    guint32               menu_revision;
    KSGtkTrayActivateFn   activate_cb;
    void                 *activate_ctx;
};

static guint g_ks_tray_seq = 0;

static const char KS_TRAY_SNI_XML[] =
    "<node>"
    "  <interface name='org.kde.StatusNotifierItem'>"
    "    <property name='Category' type='s' access='read'/>"
    "    <property name='Id' type='s' access='read'/>"
    "    <property name='Title' type='s' access='read'/>"
    "    <property name='Status' type='s' access='read'/>"
    "    <property name='IconName' type='s' access='read'/>"
    "    <property name='IconPixmap' type='a(iiay)' access='read'/>"
    "    <property name='ToolTip' type='(sa(iiay)ss)' access='read'/>"
    "    <property name='ItemIsMenu' type='b' access='read'/>"
    "    <property name='Menu' type='o' access='read'/>"
    "    <method name='Activate'>"
    "      <arg type='i' name='x' direction='in'/>"
    "      <arg type='i' name='y' direction='in'/>"
    "    </method>"
    "    <method name='SecondaryActivate'>"
    "      <arg type='i' name='x' direction='in'/>"
    "      <arg type='i' name='y' direction='in'/>"
    "    </method>"
    "    <method name='ContextMenu'>"
    "      <arg type='i' name='x' direction='in'/>"
    "      <arg type='i' name='y' direction='in'/>"
    "    </method>"
    "    <method name='Scroll'>"
    "      <arg type='i' name='delta' direction='in'/>"
    "      <arg type='s' name='orientation' direction='in'/>"
    "    </method>"
    "    <signal name='NewIcon'/>"
    "    <signal name='NewToolTip'/>"
    "    <signal name='NewStatus'><arg type='s' name='status'/></signal>"
    "  </interface>"
    "</node>";

static const char KS_TRAY_MENU_XML[] =
    "<node>"
    "  <interface name='com.canonical.dbusmenu'>"
    "    <property name='Version' type='u' access='read'/>"
    "    <property name='TextDirection' type='s' access='read'/>"
    "    <property name='Status' type='s' access='read'/>"
    "    <property name='IconThemePath' type='as' access='read'/>"
    "    <method name='GetLayout'>"
    "      <arg type='i' name='parentId' direction='in'/>"
    "      <arg type='i' name='recursionDepth' direction='in'/>"
    "      <arg type='as' name='propertyNames' direction='in'/>"
    "      <arg type='u' name='revision' direction='out'/>"
    "      <arg type='(ia{sv}av)' name='layout' direction='out'/>"
    "    </method>"
    "    <method name='GetGroupProperties'>"
    "      <arg type='ai' name='ids' direction='in'/>"
    "      <arg type='as' name='propertyNames' direction='in'/>"
    "      <arg type='a(ia{sv})' name='properties' direction='out'/>"
    "    </method>"
    "    <method name='GetProperty'>"
    "      <arg type='i' name='id' direction='in'/>"
    "      <arg type='s' name='name' direction='in'/>"
    "      <arg type='v' name='value' direction='out'/>"
    "    </method>"
    "    <method name='Event'>"
    "      <arg type='i' name='id' direction='in'/>"
    "      <arg type='s' name='eventId' direction='in'/>"
    "      <arg type='v' name='data' direction='in'/>"
    "      <arg type='u' name='timestamp' direction='in'/>"
    "    </method>"
    "    <method name='AboutToShow'>"
    "      <arg type='i' name='id' direction='in'/>"
    "      <arg type='b' name='needUpdate' direction='out'/>"
    "    </method>"
    "    <signal name='ItemsPropertiesUpdated'>"
    "      <arg type='a(ia{sv})' name='updatedProps'/>"
    "      <arg type='a(ias)' name='removedProps'/>"
    "    </signal>"
    "    <signal name='LayoutUpdated'>"
    "      <arg type='u' name='revision'/>"
    "      <arg type='i' name='parent'/>"
    "    </signal>"
    "  </interface>"
    "</node>";

static GDBusNodeInfo *g_ks_tray_sni_info  = NULL;
static GDBusNodeInfo *g_ks_tray_menu_info = NULL;

static void ks_tray_clear_items(KSGtkTray *tray)
{
    if (!tray->items) return;
    for (int i = 0; i < tray->item_count; ++i) {
        g_free(tray->items[i].label);
        g_free(tray->items[i].command_id);
    }
    g_free(tray->items);
    tray->items = NULL;
    tray->item_count = 0;
}

static void ks_tray_set_items(KSGtkTray *tray,
                               const KSGtkTrayMenuItem *items,
                               int item_count)
{
    ks_tray_clear_items(tray);
    if (!items || item_count <= 0) return;
    tray->items = g_new0(KSGtkTrayItem, item_count);
    tray->item_count = item_count;
    for (int i = 0; i < item_count; ++i) {
        tray->items[i].id           = i + 1;
        tray->items[i].label        = items[i].label
            ? g_strdup(items[i].label) : NULL;
        tray->items[i].command_id   = items[i].command_id
            ? g_strdup(items[i].command_id) : NULL;
        tray->items[i].enabled      = items[i].enabled ? 1 : 0;
        tray->items[i].is_separator = items[i].is_separator ? 1 : 0;
    }
}

/* ---------------------------------------------------------------- */
/* SNI 메서드/프로퍼티 핸들러                                       */
/* ---------------------------------------------------------------- */

static void ks_tray_sni_method(GDBusConnection *conn,
                                const gchar     *sender,
                                const gchar     *object_path,
                                const gchar     *interface_name,
                                const gchar     *method_name,
                                GVariant        *parameters,
                                GDBusMethodInvocation *inv,
                                gpointer         user_data)
{
    (void) conn; (void) sender; (void) object_path;
    (void) interface_name; (void) parameters;
    KSGtkTray *tray = (KSGtkTray *) user_data;

    if (g_strcmp0(method_name, "Activate") == 0) {
        if (tray->activate_cb) tray->activate_cb("", tray->activate_ctx);
        g_dbus_method_invocation_return_value(inv, NULL);
    } else if (g_strcmp0(method_name, "SecondaryActivate") == 0
            || g_strcmp0(method_name, "ContextMenu") == 0
            || g_strcmp0(method_name, "Scroll") == 0) {
        /* 무시 — 메뉴는 셸이 직접 그려준다. */
        g_dbus_method_invocation_return_value(inv, NULL);
    } else {
        g_dbus_method_invocation_return_error(
            inv, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD,
            "Unknown method %s", method_name);
    }
}

static GVariant *ks_tray_sni_get_property(GDBusConnection *conn,
                                           const gchar     *sender,
                                           const gchar     *object_path,
                                           const gchar     *interface_name,
                                           const gchar     *property_name,
                                           GError         **error,
                                           gpointer         user_data)
{
    (void) conn; (void) sender; (void) object_path; (void) interface_name;
    KSGtkTray *tray = (KSGtkTray *) user_data;

    if (g_strcmp0(property_name, "Category") == 0) {
        return g_variant_new_string("ApplicationStatus");
    }
    if (g_strcmp0(property_name, "Id") == 0) {
        return g_variant_new_string(tray->app_id ? tray->app_id : "kalsae");
    }
    if (g_strcmp0(property_name, "Title") == 0) {
        return g_variant_new_string(tray->app_id ? tray->app_id : "Kalsae");
    }
    if (g_strcmp0(property_name, "Status") == 0) {
        return g_variant_new_string("Active");
    }
    if (g_strcmp0(property_name, "IconName") == 0) {
        /* 절대 경로 아이콘은 IconName으로 주면 셸이 폴백 처리한다.
         * 비어 있으면 빈 문자열을 반환해 셸의 기본 아이콘을 사용. */
        return g_variant_new_string(tray->icon_path ? tray->icon_path : "");
    }
    if (g_strcmp0(property_name, "IconPixmap") == 0) {
        return g_variant_new("a(iiay)", NULL);
    }
    if (g_strcmp0(property_name, "ToolTip") == 0) {
        const char *tip = tray->tooltip ? tray->tooltip : "";
        GVariantBuilder pix;
        g_variant_builder_init(&pix, G_VARIANT_TYPE("a(iiay)"));
        return g_variant_new("(sa(iiay)ss)", "", &pix, tip, "");
    }
    if (g_strcmp0(property_name, "ItemIsMenu") == 0) {
        /* false = 좌클릭 시 Activate 호출, true이면 메뉴만 열림. */
        return g_variant_new_boolean(FALSE);
    }
    if (g_strcmp0(property_name, "Menu") == 0) {
        return g_variant_new_object_path(KS_TRAY_MENU_PATH);
    }
    g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_PROPERTY,
                "Unknown SNI property %s", property_name);
    return NULL;
}

static const GDBusInterfaceVTable ks_tray_sni_vtable = {
    .method_call  = ks_tray_sni_method,
    .get_property = ks_tray_sni_get_property,
    .set_property = NULL,
    .padding      = { 0 },
};

/* ---------------------------------------------------------------- */
/* DBusMenu 빌더 헬퍼                                                */
/* ---------------------------------------------------------------- */

/* 단일 항목의 a{sv} 프로퍼티 dict를 만든다(GetLayout/GetGroupProperties
 * 양쪽에서 공유). */
static GVariant *ks_tray_item_props(const KSGtkTrayItem *item)
{
    GVariantBuilder b;
    g_variant_builder_init(&b, G_VARIANT_TYPE("a{sv}"));
    if (item->is_separator) {
        g_variant_builder_add(&b, "{sv}", "type",
                              g_variant_new_string("separator"));
    } else {
        if (item->label) {
            g_variant_builder_add(&b, "{sv}", "label",
                                  g_variant_new_string(item->label));
        }
        g_variant_builder_add(&b, "{sv}", "enabled",
                              g_variant_new_boolean(item->enabled ? TRUE : FALSE));
        g_variant_builder_add(&b, "{sv}", "visible",
                              g_variant_new_boolean(TRUE));
    }
    return g_variant_builder_end(&b);
}

/* 루트 (id=0)의 자식 트리를 (ia{sv}av) 형태로 구성. */
static GVariant *ks_tray_build_layout(KSGtkTray *tray)
{
    /* root props: children-display=submenu */
    GVariantBuilder root_props;
    g_variant_builder_init(&root_props, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&root_props, "{sv}", "children-display",
                          g_variant_new_string("submenu"));

    /* children: av (각 자식은 v(ia{sv}av)) */
    GVariantBuilder children;
    g_variant_builder_init(&children, G_VARIANT_TYPE("av"));
    for (int i = 0; i < tray->item_count; ++i) {
        GVariant *child_props = ks_tray_item_props(&tray->items[i]);
        GVariantBuilder empty_children;
        g_variant_builder_init(&empty_children, G_VARIANT_TYPE("av"));
        GVariant *child = g_variant_new(
            "(i@a{sv}av)",
            tray->items[i].id, child_props, &empty_children);
        g_variant_builder_add(&children, "v", child);
    }
    return g_variant_new("(ia{sv}av)", 0, &root_props, &children);
}

static void ks_tray_menu_method(GDBusConnection *conn,
                                 const gchar     *sender,
                                 const gchar     *object_path,
                                 const gchar     *interface_name,
                                 const gchar     *method_name,
                                 GVariant        *parameters,
                                 GDBusMethodInvocation *inv,
                                 gpointer         user_data)
{
    (void) conn; (void) sender; (void) object_path; (void) interface_name;
    KSGtkTray *tray = (KSGtkTray *) user_data;

    if (g_strcmp0(method_name, "GetLayout") == 0) {
        GVariant *layout = ks_tray_build_layout(tray);
        g_dbus_method_invocation_return_value(
            inv, g_variant_new("(u@(ia{sv}av))",
                                tray->menu_revision, layout));
        return;
    }
    if (g_strcmp0(method_name, "GetGroupProperties") == 0) {
        GVariantIter *ids_iter = NULL;
        GVariantIter *names_iter = NULL;
        g_variant_get(parameters, "(aias)", &ids_iter, &names_iter);
        if (names_iter) g_variant_iter_free(names_iter);

        GVariantBuilder result;
        g_variant_builder_init(&result, G_VARIANT_TYPE("a(ia{sv})"));
        gint32 id;
        while (g_variant_iter_next(ids_iter, "i", &id)) {
            if (id == 0) continue;
            for (int i = 0; i < tray->item_count; ++i) {
                if (tray->items[i].id == id) {
                    g_variant_builder_add(
                        &result, "(i@a{sv})",
                        id, ks_tray_item_props(&tray->items[i]));
                    break;
                }
            }
        }
        g_variant_iter_free(ids_iter);
        g_dbus_method_invocation_return_value(
            inv, g_variant_new("(a(ia{sv}))", &result));
        return;
    }
    if (g_strcmp0(method_name, "GetProperty") == 0) {
        gint32 id;
        const gchar *name;
        g_variant_get(parameters, "(i&s)", &id, &name);
        for (int i = 0; i < tray->item_count; ++i) {
            if (tray->items[i].id != id) continue;
            if (g_strcmp0(name, "label") == 0 && tray->items[i].label) {
                g_dbus_method_invocation_return_value(
                    inv, g_variant_new("(v)",
                        g_variant_new_string(tray->items[i].label)));
                return;
            }
            if (g_strcmp0(name, "enabled") == 0) {
                g_dbus_method_invocation_return_value(
                    inv, g_variant_new("(v)",
                        g_variant_new_boolean(tray->items[i].enabled)));
                return;
            }
            break;
        }
        g_dbus_method_invocation_return_error(
            inv, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_PROPERTY,
            "Unknown property %s for id %d", name, id);
        return;
    }
    if (g_strcmp0(method_name, "Event") == 0) {
        gint32 id;
        const gchar *event_id;
        GVariant *data;
        guint32 ts;
        g_variant_get(parameters, "(i&sv u)", &id, &event_id, &data, &ts);
        if (data) g_variant_unref(data);
        if (g_strcmp0(event_id, "clicked") == 0 && id > 0) {
            for (int i = 0; i < tray->item_count; ++i) {
                if (tray->items[i].id == id
                 && !tray->items[i].is_separator
                 && tray->items[i].command_id
                 && tray->activate_cb) {
                    tray->activate_cb(tray->items[i].command_id,
                                      tray->activate_ctx);
                    break;
                }
            }
        }
        g_dbus_method_invocation_return_value(inv, NULL);
        return;
    }
    if (g_strcmp0(method_name, "AboutToShow") == 0) {
        g_dbus_method_invocation_return_value(
            inv, g_variant_new("(b)", FALSE));
        return;
    }

    g_dbus_method_invocation_return_error(
        inv, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD,
        "Unknown DBusMenu method %s", method_name);
}

static GVariant *ks_tray_menu_get_property(GDBusConnection *conn,
                                            const gchar     *sender,
                                            const gchar     *object_path,
                                            const gchar     *interface_name,
                                            const gchar     *property_name,
                                            GError         **error,
                                            gpointer         user_data)
{
    (void) conn; (void) sender; (void) object_path; (void) interface_name;
    (void) user_data;
    if (g_strcmp0(property_name, "Version") == 0) {
        return g_variant_new_uint32(3);
    }
    if (g_strcmp0(property_name, "TextDirection") == 0) {
        return g_variant_new_string("ltr");
    }
    if (g_strcmp0(property_name, "Status") == 0) {
        return g_variant_new_string("normal");
    }
    if (g_strcmp0(property_name, "IconThemePath") == 0) {
        const gchar *empty[] = { NULL };
        return g_variant_new_strv(empty, 0);
    }
    g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_PROPERTY,
                "Unknown DBusMenu property %s", property_name);
    return NULL;
}

static const GDBusInterfaceVTable ks_tray_menu_vtable = {
    .method_call  = ks_tray_menu_method,
    .get_property = ks_tray_menu_get_property,
    .set_property = NULL,
    .padding      = { 0 },
};

/* ---------------------------------------------------------------- */
/* Watcher 등록                                                      */
/* ---------------------------------------------------------------- */

static int ks_tray_register_with_watcher(KSGtkTray *tray)
{
    GError *err = NULL;
    GVariant *result = g_dbus_connection_call_sync(
        tray->conn,
        KS_TRAY_WATCHER_NAME, KS_TRAY_WATCHER_PATH,
        KS_TRAY_WATCHER_IFACE, "RegisterStatusNotifierItem",
        g_variant_new("(s)", tray->bus_name),
        NULL, G_DBUS_CALL_FLAGS_NONE, 5000, NULL, &err);
    if (err) {
        g_warning("KSTray: watcher unavailable (%s)",
                  err->message ? err->message : "no message");
        g_error_free(err);
        return 0;
    }
    if (result) g_variant_unref(result);
    return 1;
}

/* ---------------------------------------------------------------- */
/* Public API                                                        */
/* ---------------------------------------------------------------- */

KSGtkTray *ks_gtk_tray_new(void)
{
    KSGtkTray *t = g_new0(KSGtkTray, 1);
    t->menu_revision = 1;
    return t;
}

int ks_gtk_tray_install(KSGtkTray *tray,
                         const char *app_id,
                         const char *icon_path,
                         const char *tooltip,
                         const KSGtkTrayMenuItem *items,
                         int item_count,
                         KSGtkTrayActivateFn cb,
                         void *ctx)
{
    if (!tray || tray->installed) return 0;

    /* 1회 introspection 파싱 캐시. */
    if (!g_ks_tray_sni_info) {
        GError *e = NULL;
        g_ks_tray_sni_info = g_dbus_node_info_new_for_xml(
            KS_TRAY_SNI_XML, &e);
        if (e) { g_warning("KSTray: SNI XML parse failed: %s",
                            e->message); g_error_free(e); return 0; }
    }
    if (!g_ks_tray_menu_info) {
        GError *e = NULL;
        g_ks_tray_menu_info = g_dbus_node_info_new_for_xml(
            KS_TRAY_MENU_XML, &e);
        if (e) { g_warning("KSTray: DBusMenu XML parse failed: %s",
                            e->message); g_error_free(e); return 0; }
    }

    /* 세션 버스 연결. */
    GError *err = NULL;
    GDBusConnection *conn = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &err);
    if (err || !conn) {
        g_warning("KSTray: session bus unavailable: %s",
                  err ? err->message : "(no err)");
        if (err) g_error_free(err);
        return 0;
    }
    tray->conn = conn;

    /* 메타데이터 보관. */
    clear_string(&tray->app_id);
    clear_string(&tray->icon_path);
    clear_string(&tray->tooltip);
    if (app_id    && *app_id)    tray->app_id    = g_strdup(app_id);
    if (icon_path && *icon_path) tray->icon_path = g_strdup(icon_path);
    if (tooltip   && *tooltip)   tray->tooltip   = g_strdup(tooltip);
    ks_tray_set_items(tray, items, item_count);
    tray->activate_cb  = cb;
    tray->activate_ctx = ctx;

    /* 고유 버스 이름 생성. */
    g_free(tray->bus_name);
    tray->bus_name = g_strdup_printf(
        "org.kde.StatusNotifierItem-%d-%u",
        (int) getpid(), ++g_ks_tray_seq);

    /* 객체 등록. */
    tray->sni_reg_id = g_dbus_connection_register_object(
        tray->conn, KS_TRAY_SNI_PATH,
        g_ks_tray_sni_info->interfaces[0],
        &ks_tray_sni_vtable, tray, NULL, &err);
    if (err) {
        g_warning("KSTray: SNI register failed: %s", err->message);
        g_error_free(err); err = NULL;
    }
    tray->menu_reg_id = g_dbus_connection_register_object(
        tray->conn, KS_TRAY_MENU_PATH,
        g_ks_tray_menu_info->interfaces[0],
        &ks_tray_menu_vtable, tray, NULL, &err);
    if (err) {
        g_warning("KSTray: DBusMenu register failed: %s", err->message);
        g_error_free(err); err = NULL;
    }

    /* 버스 이름 소유. */
    tray->owner_id = g_bus_own_name_on_connection(
        tray->conn, tray->bus_name,
        G_BUS_NAME_OWNER_FLAGS_NONE,
        NULL, NULL, NULL, NULL);

    /* Watcher 등록 시도. */
    int rc = ks_tray_register_with_watcher(tray);
    tray->installed = rc;
    return rc;
}

void ks_gtk_tray_set_tooltip(KSGtkTray *tray, const char *tooltip)
{
    if (!tray) return;
    clear_string(&tray->tooltip);
    if (tooltip && *tooltip) tray->tooltip = g_strdup(tooltip);
    if (tray->installed && tray->conn) {
        g_dbus_connection_emit_signal(
            tray->conn, NULL, KS_TRAY_SNI_PATH, KS_TRAY_SNI_IFACE,
            "NewToolTip", NULL, NULL);
    }
}

void ks_gtk_tray_set_menu(KSGtkTray *tray,
                           const KSGtkTrayMenuItem *items,
                           int item_count)
{
    if (!tray) return;
    ks_tray_set_items(tray, items, item_count);
    tray->menu_revision++;
    if (tray->installed && tray->conn) {
        g_dbus_connection_emit_signal(
            tray->conn, NULL, KS_TRAY_MENU_PATH, KS_TRAY_MENU_IFACE,
            "LayoutUpdated",
            g_variant_new("(ui)", tray->menu_revision, 0),
            NULL);
    }
}

void ks_gtk_tray_remove(KSGtkTray *tray)
{
    if (!tray || !tray->installed) return;
    if (tray->conn) {
        if (tray->sni_reg_id) {
            g_dbus_connection_unregister_object(tray->conn, tray->sni_reg_id);
            tray->sni_reg_id = 0;
        }
        if (tray->menu_reg_id) {
            g_dbus_connection_unregister_object(tray->conn, tray->menu_reg_id);
            tray->menu_reg_id = 0;
        }
    }
    if (tray->owner_id) {
        g_bus_unown_name(tray->owner_id);
        tray->owner_id = 0;
    }
    tray->installed = 0;
}

void ks_gtk_tray_free(KSGtkTray *tray)
{
    if (!tray) return;
    ks_gtk_tray_remove(tray);
    if (tray->conn) {
        g_object_unref(tray->conn);
        tray->conn = NULL;
    }
    ks_tray_clear_items(tray);
    clear_string(&tray->bus_name);
    clear_string(&tray->app_id);
    clear_string(&tray->icon_path);
    clear_string(&tray->tooltip);
    g_free(tray);
}


