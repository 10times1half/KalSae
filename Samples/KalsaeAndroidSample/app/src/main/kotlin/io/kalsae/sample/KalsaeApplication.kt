package io.kalsae.sample

import android.app.Application

/**
 * Application entry point.
 *
 * Initialises the Kalsae Swift runtime early in the process lifecycle so that
 * the hook callbacks are registered before any Activity starts.
 */
class KalsaeApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        // The Swift JNI startup is deferred to MainActivity.onCreate() where
        // the WebView is available for hook wiring.
        // Additional application-level setup (e.g. process name guards for
        // multi-process use) can go here.
    }
}
