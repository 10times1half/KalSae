#include <jni.h>
#include <cstdint>
#include <string>

namespace {
JavaVM* g_vm = nullptr;
jclass g_callbacksClass = nullptr;

jmethodID g_evalJs = nullptr;
jmethodID g_loadUrl = nullptr;
jmethodID g_credSet = nullptr;
jmethodID g_credGet = nullptr;
jmethodID g_credDelete = nullptr;
jmethodID g_credList = nullptr;

JNIEnv* getEnv() {
    if (g_vm == nullptr) {
        return nullptr;
    }

    JNIEnv* env = nullptr;
    const jint status = g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (status == JNI_OK) {
        return env;
    }

    if (status == JNI_EDETACHED) {
        if (g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
            return env;
        }
    }

    return nullptr;
}

void callString(jmethodID method, const char* value) {
    JNIEnv* env = getEnv();
    if (env == nullptr || g_callbacksClass == nullptr || method == nullptr || value == nullptr) {
        return;
    }

    jstring arg = env->NewStringUTF(value);
    if (arg == nullptr) {
        return;
    }
    env->CallStaticVoidMethod(g_callbacksClass, method, arg);
    env->DeleteLocalRef(arg);
}

void callCredential(jmethodID method, int32_t requestId, const char* json) {
    JNIEnv* env = getEnv();
    if (env == nullptr || g_callbacksClass == nullptr || method == nullptr || json == nullptr) {
        return;
    }

    jstring arg = env->NewStringUTF(json);
    if (arg == nullptr) {
        return;
    }
    env->CallStaticVoidMethod(g_callbacksClass, method, static_cast<jint>(requestId), arg);
    env->DeleteLocalRef(arg);
}

extern "C" void callbackEvaluateJs(const char* script) {
    callString(g_evalJs, script);
}

extern "C" void callbackLoadUrl(const char* url) {
    callString(g_loadUrl, url);
}

extern "C" void callbackCredentialSet(int32_t requestId, const char* requestJson) {
    callCredential(g_credSet, requestId, requestJson);
}

extern "C" void callbackCredentialGet(int32_t requestId, const char* requestJson) {
    callCredential(g_credGet, requestId, requestJson);
}

extern "C" void callbackCredentialDelete(int32_t requestId, const char* requestJson) {
    callCredential(g_credDelete, requestId, requestJson);
}

extern "C" void callbackCredentialList(int32_t requestId, const char* requestJson) {
    callCredential(g_credList, requestId, requestJson);
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    g_vm = vm;
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_io_kalsae_sample_KalsaeNativeCallbacks_nativeInitBridge(JNIEnv* env, jclass) {
    jclass localClass = env->FindClass("io/kalsae/sample/KalsaeNativeCallbacks");
    if (localClass == nullptr) {
        return JNI_FALSE;
    }

    if (g_callbacksClass != nullptr) {
        env->DeleteGlobalRef(g_callbacksClass);
        g_callbacksClass = nullptr;
    }
    g_callbacksClass = static_cast<jclass>(env->NewGlobalRef(localClass));
    env->DeleteLocalRef(localClass);

    if (g_callbacksClass == nullptr) {
        return JNI_FALSE;
    }

    g_evalJs = env->GetStaticMethodID(g_callbacksClass, "dispatchEvaluateJs", "(Ljava/lang/String;)V");
    g_loadUrl = env->GetStaticMethodID(g_callbacksClass, "dispatchLoadUrl", "(Ljava/lang/String;)V");
    g_credSet = env->GetStaticMethodID(g_callbacksClass, "dispatchCredentialSet", "(ILjava/lang/String;)V");
    g_credGet = env->GetStaticMethodID(g_callbacksClass, "dispatchCredentialGet", "(ILjava/lang/String;)V");
    g_credDelete = env->GetStaticMethodID(g_callbacksClass, "dispatchCredentialDelete", "(ILjava/lang/String;)V");
    g_credList = env->GetStaticMethodID(g_callbacksClass, "dispatchCredentialList", "(ILjava/lang/String;)V");

    if (g_evalJs == nullptr || g_loadUrl == nullptr || g_credSet == nullptr || g_credGet == nullptr
        || g_credDelete == nullptr || g_credList == nullptr) {
        return JNI_FALSE;
    }

    return JNI_TRUE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_io_kalsae_sample_KalsaeNativeCallbacks_nativeGetEvaluateJsCallbackPtr(JNIEnv*, jclass) {
    return reinterpret_cast<jlong>(&callbackEvaluateJs);
}

extern "C" JNIEXPORT jlong JNICALL
Java_io_kalsae_sample_KalsaeNativeCallbacks_nativeGetLoadUrlCallbackPtr(JNIEnv*, jclass) {
    return reinterpret_cast<jlong>(&callbackLoadUrl);
}

extern "C" JNIEXPORT jlong JNICALL
Java_io_kalsae_sample_KalsaeNativeCallbacks_nativeGetCredentialSetCallbackPtr(JNIEnv*, jclass) {
    return reinterpret_cast<jlong>(&callbackCredentialSet);
}

extern "C" JNIEXPORT jlong JNICALL
Java_io_kalsae_sample_KalsaeNativeCallbacks_nativeGetCredentialGetCallbackPtr(JNIEnv*, jclass) {
    return reinterpret_cast<jlong>(&callbackCredentialGet);
}

extern "C" JNIEXPORT jlong JNICALL
Java_io_kalsae_sample_KalsaeNativeCallbacks_nativeGetCredentialDeleteCallbackPtr(JNIEnv*, jclass) {
    return reinterpret_cast<jlong>(&callbackCredentialDelete);
}

extern "C" JNIEXPORT jlong JNICALL
Java_io_kalsae_sample_KalsaeNativeCallbacks_nativeGetCredentialListCallbackPtr(JNIEnv*, jclass) {
    return reinterpret_cast<jlong>(&callbackCredentialList);
}
