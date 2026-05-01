package io.kalsae.sample

/**
 * Kotlin bindings for the Kalsae Swift JNI layer.
 *
 * These declarations map to the `@_cdecl` functions exported by
 * `Sources/KalsaePlatformAndroid/JNI/KSAndroidJNI.swift`.
 *
 * The Swift shared library (`libKalsaePlatformAndroid.so`) must be placed in
 * `app/src/main/jniLibs/<abi>/` before building.  Build it with:
 *   swift build --swift-sdk aarch64-unknown-linux-android26
 *
 * Naming: the `@_cdecl` symbol names in Swift map directly to the `external`
 * function names here — no JNI mangling is needed for `@_cdecl` exports.
 */
object KalsaeJNI {

    init {
        System.loadLibrary("KalsaePlatformAndroid")
    }

    // -------------------------------------------------------------------------
    // Hook registration — call before startup()
    // -------------------------------------------------------------------------

    /** Register a C function pointer that Swift calls to evaluate JS. */
    external fun registerEvaluateJs(fn: Long)

    /** Register a C function pointer that Swift calls to load a URL. */
    external fun registerLoadUrl(fn: Long)

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    /**
     * Initialises the Swift runtime.  Returns 0 on success.
     * Must be called from the main thread after hook registration.
     */
    external fun startup(): Int

    /** Signal that the Activity's WebView is ready. Flushes any queued URL. */
    external fun onViewCreated()

    /** Navigates the WebView to the given URL. */
    external fun navigate(url: String)

    /** Call from Activity.onResume. */
    external fun onResume()

    /** Call from Activity.onPause. */
    external fun onPause()

    // -------------------------------------------------------------------------
    // Messaging
    // -------------------------------------------------------------------------

    /**
     * Forward a JSON message from JS to Swift.
     * Call from your @JavascriptInterface `postMessage` method.
     */
    external fun onInboundMessage(json: String)

    /**
     * Returns the composite document-start JavaScript string.
     * Inject it via WebViewCompat.addDocumentStartJavaScript().
     * Must be called from the main thread after startup().
     */
    external fun documentStartScript(): String
}
