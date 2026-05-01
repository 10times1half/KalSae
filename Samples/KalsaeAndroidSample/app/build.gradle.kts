plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "io.kalsae.sample"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.kalsae.sample"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    // Place the Swift shared library in jniLibs so it is packaged into the APK.
    // After cross-compiling with:
    //   swift build --swift-sdk aarch64-unknown-linux-android26
    // copy the resulting .so here:
    //   src/main/jniLibs/arm64-v8a/libKalsaePlatformAndroid.so
    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.webkit)
}
