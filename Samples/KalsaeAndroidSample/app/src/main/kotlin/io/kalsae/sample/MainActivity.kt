package io.kalsae.sample

import android.annotation.SuppressLint
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

/**
 * MainActivity for the Kalsae Android sample (API 26+, targetSdk 35).
 *
 * Wiring overview:
 *  1. Register C callbacks so Swift can call back into the WebView.
 *  2. Call KalsaeJNI.startup() to initialise the Swift runtime.
 *  3. Set up the WebView with the document-start script and JS interface.
 *  4. Call KalsaeJNI.onViewCreated() to flush any queued navigation URL.
 *
 * The Swift JNI entry points live in:
 *   Sources/KalsaePlatformAndroid/JNI/KSAndroidJNI.swift
 */
class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        webView = findViewById(R.id.webview)

        setupWebView()
        initKalsaeRuntime()
    }

    // -------------------------------------------------------------------------
    // WebView setup
    // -------------------------------------------------------------------------

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
        }

        // Bridge object exposed to JS as window.__KS_bridge
        webView.addJavascriptInterface(WebAppInterface(), "__KS_bridge")

        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                super.onPageFinished(view, url)
            }
        }
    }

    // -------------------------------------------------------------------------
    // Kalsae runtime initialisation
    // -------------------------------------------------------------------------

    private fun initKalsaeRuntime() {
        // 1. Register the evaluateJavascript callback (Swift → JS).
        //    The Long values here are C function pointer addresses obtained
        //    from a JNI helper (see KalsaeCallbacks.kt in a full project).
        //    For this sample they are wired via a simpler Kotlin lambda bridge
        //    that marshals calls through a registered native trampoline.
        //
        //    Minimal integration: use the document-start injection path only,
        //    and post messages back via evaluateJavascript directly.
        //    Full function-pointer wiring requires a thin C/JNI trampoline;
        //    see the README for details.
        //
        //    For demonstration, we wire the closures via a companion trampoline
        //    that the Swift side calls through the registered function pointers.
        //    (Trampoline registration omitted here for brevity — replace with
        //    your JNI trampoline address obtained from a native helper.)

        // 2. Start the Swift runtime.
        val result = KalsaeJNI.startup()
        check(result == 0) { "KalsaeJNI.startup() failed: $result" }

        // 3. Inject the document-start script (Kalsae IPC runtime + user scripts).
        val script = KalsaeJNI.documentStartScript()
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(webView, script, setOf("*"))
        } else {
            // Fallback: re-inject on each page load via onPageStarted.
            webView.webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
                    view.evaluateJavascript(script, null)
                }
            }
        }

        // 4. Navigate to the app entry point.
        KalsaeJNI.navigate("ks://localhost/")

        // 5. Signal that the WebView is ready, flushing any queued URL.
        KalsaeJNI.onViewCreated()
    }

    // -------------------------------------------------------------------------
    // Activity lifecycle
    // -------------------------------------------------------------------------

    override fun onResume() {
        super.onResume()
        KalsaeJNI.onResume()
    }

    override fun onPause() {
        KalsaeJNI.onPause()
        super.onPause()
    }

    // -------------------------------------------------------------------------
    // JS → Swift bridge
    // -------------------------------------------------------------------------

    /** Exposed to JS as `window.__KS_bridge`. */
    inner class WebAppInterface {
        @JavascriptInterface
        fun postMessage(json: String) {
            // Delivered on a background thread by Android — KS_android_on_inbound_message
            // is documented as thread-safe.
            KalsaeJNI.onInboundMessage(json)
        }
    }
}
