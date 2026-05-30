package io.kalsae.sample

/**
 * JNI callback trampoline provider.
 *
 * Swift expects raw C function pointers. This object exposes pointer addresses
 * from a small C++ shim and wires them to Kotlin dispatch functions.
 */
object KalsaeNativeCallbacks {

    init {
        System.loadLibrary("kalsae_callbacks")
    }

    private external fun nativeInitBridge(): Boolean
    private external fun nativeGetEvaluateJsCallbackPtr(): Long
    private external fun nativeGetLoadUrlCallbackPtr(): Long
    private external fun nativeGetCredentialSetCallbackPtr(): Long
    private external fun nativeGetCredentialGetCallbackPtr(): Long
    private external fun nativeGetCredentialDeleteCallbackPtr(): Long
    private external fun nativeGetCredentialListCallbackPtr(): Long

    fun registerIntoSwift() {
        check(nativeInitBridge()) { "Failed to initialize native callback bridge" }
        KalsaeJNI.registerEvaluateJs(nativeGetEvaluateJsCallbackPtr())
        KalsaeJNI.registerLoadUrl(nativeGetLoadUrlCallbackPtr())
        KalsaeJNI.registerCredentialSet(nativeGetCredentialSetCallbackPtr())
        KalsaeJNI.registerCredentialGet(nativeGetCredentialGetCallbackPtr())
        KalsaeJNI.registerCredentialDelete(nativeGetCredentialDeleteCallbackPtr())
        KalsaeJNI.registerCredentialList(nativeGetCredentialListCallbackPtr())
    }

    @JvmStatic
    fun dispatchEvaluateJs(script: String) {
        KalsaeHostBridge.evaluateJs(script)
    }

    @JvmStatic
    fun dispatchLoadUrl(url: String) {
        KalsaeHostBridge.loadUrl(url)
    }

    @JvmStatic
    fun dispatchCredentialSet(requestId: Int, requestJson: String) {
        KalsaeHostBridge.credentialSet(requestId, requestJson)
    }

    @JvmStatic
    fun dispatchCredentialGet(requestId: Int, requestJson: String) {
        KalsaeHostBridge.credentialGet(requestId, requestJson)
    }

    @JvmStatic
    fun dispatchCredentialDelete(requestId: Int, requestJson: String) {
        KalsaeHostBridge.credentialDelete(requestId, requestJson)
    }

    @JvmStatic
    fun dispatchCredentialList(requestId: Int, requestJson: String) {
        KalsaeHostBridge.credentialList(requestId, requestJson)
    }
}
