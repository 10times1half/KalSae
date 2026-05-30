package io.kalsae.sample

import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import java.lang.ref.WeakReference

/**
 * Runtime bridge target for native callback trampolines.
 */
object KalsaeHostBridge {

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var webViewRef: WeakReference<WebView>? = null

    @Volatile
    private var credentialStore: AndroidCredentialStore? = null

    fun attach(webView: WebView, store: AndroidCredentialStore) {
        webViewRef = WeakReference(webView)
        credentialStore = store
    }

    fun evaluateJs(script: String) {
        mainHandler.post {
            webViewRef?.get()?.evaluateJavascript(script, null)
        }
    }

    fun loadUrl(url: String) {
        mainHandler.post {
            webViewRef?.get()?.loadUrl(url)
        }
    }

    fun credentialSet(requestId: Int, requestJson: String) {
        credentialStore?.handleSet(requestId, requestJson)
            ?: KalsaeJNI.onCredentialResult(requestId, "{\"ok\":false,\"error\":\"credential store unavailable\"}")
    }

    fun credentialGet(requestId: Int, requestJson: String) {
        credentialStore?.handleGet(requestId, requestJson)
            ?: KalsaeJNI.onCredentialResult(requestId, "{\"ok\":false,\"error\":\"credential store unavailable\"}")
    }

    fun credentialDelete(requestId: Int, requestJson: String) {
        credentialStore?.handleDelete(requestId, requestJson)
            ?: KalsaeJNI.onCredentialResult(requestId, "{\"ok\":false,\"error\":\"credential store unavailable\"}")
    }

    fun credentialList(requestId: Int, requestJson: String) {
        credentialStore?.handleList(requestId, requestJson)
            ?: KalsaeJNI.onCredentialResult(requestId, "{\"ok\":false,\"error\":\"credential store unavailable\"}")
    }
}
