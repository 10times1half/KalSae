package io.kalsae.sample

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject

/**
 * Minimal credential store helper for Kalsae Android host integration.
 *
 * This class focuses on request/response translation and encrypted storage.
 * Wiring the native function-pointer registration is host-specific and intentionally
 * left to app code that bridges JNI callbacks to these handlers.
 */
class AndroidCredentialStore(context: Context) {

    private val prefs = run {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        EncryptedSharedPreferences.create(
            context,
            "kalsae_credentials",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    fun handleSet(requestId: Int, requestJson: String) {
        try {
            val request = JSONObject(requestJson)
            val service = request.getString("service")
            val account = request.getString("account")
            val secretBase64 = request.getString("secretBase64")

            prefs.edit().putString(key(service, account), secretBase64).apply()
            replyOk(requestId)
        } catch (t: Throwable) {
            replyError(requestId, t)
        }
    }

    fun handleGet(requestId: Int, requestJson: String) {
        try {
            val request = JSONObject(requestJson)
            val service = request.getString("service")
            val account = request.getString("account")

            val secretBase64 = prefs.getString(key(service, account), null)
            val payload = JSONObject().put("secretBase64", secretBase64)
            replyOk(requestId, payload)
        } catch (t: Throwable) {
            replyError(requestId, t)
        }
    }

    fun handleDelete(requestId: Int, requestJson: String) {
        try {
            val request = JSONObject(requestJson)
            val service = request.getString("service")
            val account = request.getString("account")

            prefs.edit().remove(key(service, account)).apply()
            replyOk(requestId)
        } catch (t: Throwable) {
            replyError(requestId, t)
        }
    }

    fun handleList(requestId: Int, requestJson: String) {
        try {
            val request = JSONObject(requestJson)
            val service = request.getString("service")
            val prefix = "$service::"
            val accounts = prefs.all.keys
                .asSequence()
                .filter { it.startsWith(prefix) }
                .map { it.removePrefix(prefix) }
                .sorted()
                .toList()

            val payload = JSONObject().put("accounts", JSONArray(accounts))
            replyOk(requestId, payload)
        } catch (t: Throwable) {
            replyError(requestId, t)
        }
    }

    private fun key(service: String, account: String): String = "$service::$account"

    private fun replyOk(requestId: Int, payload: JSONObject? = null) {
        val envelope = JSONObject().put("ok", true)
        if (payload != null) {
            envelope.put("payload", payload)
        }
        KalsaeJNI.onCredentialResult(requestId, envelope.toString())
    }

    private fun replyError(requestId: Int, error: Throwable) {
        val message = error.message ?: "credential operation failed"
        val envelope = JSONObject()
            .put("ok", false)
            .put("error", message)
        KalsaeJNI.onCredentialResult(requestId, envelope.toString())
    }
}
