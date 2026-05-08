# RFC-007 — Android 플랫폼 Release 상태 전환

| 항목 | 내용 |
|------|------|
| 상태 | 초안 (Draft) |
| 날짜 | 2026-05-09 |
| 영향 범위 | `KalsaePlatformAndroid`, `KalsaeCLI` (PackagerAndroid, BuildCommand), `Kalsae` (KSApp) |
| 관련 | RFC-005 (ios-release), `PackagerMac.swift`, `BuildCommand.swift` |

---

## 1. 동기 (Motivation)

Kalsae의 Android PAL(Platform Abstraction Layer)은 현재 **preview** 상태다. 모든 PAL 백엔드 인터페이스가 구현되어 있고 `KSApp.boot` 통합도 완료되었으나, 다음 항목이 부족해 실제 앱 배포에 사용할 수 없다:

1. **Android APK 패키저**가 없어 `kalsae build`가 Android 산출물을 생성하지 못함
2. **Dialog/Menu 백엔드가 핸들러 주입형**으로만 동작하여 기본 JNI 구현이 없음
3. **통합 테스트**가 부족함
4. **문서화**가 미흡함

본 RFC는 Android 플랫폼을 preview → stable로 전환하기 위한 구체적인 작업 항목을 정의한다.

---

## 2. 목표 / 비목표

### 목표

- `kalsae build`가 macOS/Linux 호스트에서 Android Gradle 프로젝트를 생성할 수 있다
- Android PAL 백엔드가 기본 JNI 구현을 제공한다 (Dialog, Menu)
- Android 크로스 컴파일 CI가 구성된다
- 문서화가 완료된다

### 비목표

- APK 코드사이닝 자동화 (Android Studio/Gradle 수동 설정 필요)
- Google Play Store 업로드 자동화
- Android 전용 플러그인 (예: 위치, 카메라)
- `kalsae dev` Android 지원 (현재 범위 외)
- Windows 호스트에서 Android 패키징 (macOS/Linux 우선)

---

## 3. 설계

### 3.1 Android 패키저 (`PackagerAndroid.swift`)

iOS의 `PackagerIOS.swift`(RFC-005)와 macOS의 `PackagerMac.swift`를 모델로 Android Gradle 프로젝트 생성기를 구현한다.

#### 3.1.1 Android 산출물 구조

`kalsae build --target android`는 다음 구조의 Gradle 프로젝트를 생성한다:

```
<output>/
  <App>-<version>-android/
    build.gradle.kts                    # 최상위 (plugins 선언)
    settings.gradle.kts                 # rootProject.name
    gradle/
      libs.versions.toml                # 버전 카탈로그
    gradlew                             # Gradle Wrapper (Linux/macOS)
    gradlew.bat                         # Gradle Wrapper (Windows)
    gradle/wrapper/
      gradle-wrapper.jar
      gradle-wrapper.properties
    app/
      build.gradle.kts                  # applicationId, versionCode, versionName
      src/main/
        AndroidManifest.xml             # 생성 (identifier, version, deepLink schemes)
        assets/
          Kalsae.json                   # rewrite (frontendDist="assets", devtools=false)
          index.html                    # 프론트엔드 dist 내용
          ...                           # 기타 프론트엔드 자산
        jniLibs/
          arm64-v8a/
            libKalsaePlatformAndroid.so # SwiftPM 크로스 컴파일 산출물
        kotlin/
          io/kalsae/app/
            MainActivity.kt             # Kalsae JNI 호출 템플릿
            KalsaeJNI.kt                # JNI 헬퍼 (evaluateJs, loadUrl, postMessage)
            WebAppInterface.kt          # @JavascriptInterface
        res/
          values/
            strings.xml                 # app_name
            themes.xml                  # Theme.KalsaeApp
          mipmap-mdpi/
            ic_launcher.png             # 48×48
            ic_launcher_round.png       # 48×48
          mipmap-hdpi/
            ic_launcher.png             # 72×72
            ic_launcher_round.png       # 72×72
          mipmap-xhdpi/
            ic_launcher.png             # 96×96
            ic_launcher_round.png       # 96×96
          mipmap-xxhdpi/
            ic_launcher.png             # 144×144
            ic_launcher_round.png       # 144×144
          mipmap-xxxhdpi/
            ic_launcher.png             # 192×192
            ic_launcher_round.png       # 192×192
```

#### 3.1.2 `KSPackager.AndroidOptions` 구조체

```swift
extension KSPackager {
    public struct AndroidOptions: Sendable {
        public var executablePath: URL       // .build/release/libKalsaePlatformAndroid.so
        public var configPath: URL           // Kalsae.json
        public var frontendDist: URL?
        public var output: URL               // dist/<App>-<ver>-android/
        public var appName: String
        public var version: String
        public var identifier: String
        public var iconPath: URL?            // 1024x1024 PNG 소스
        public var minimumAPILevel: Int      // 기본 26
        public var targetAPILevel: Int       // 기본 35
        public var deepLinkSchemes: [String] // AndroidManifest.xml intent-filter
        public var stripSourceMaps: Bool
        public var stripExtensions: [String]

        public init(
            executablePath: URL,
            configPath: URL,
            frontendDist: URL?,
            output: URL,
            appName: String,
            version: String,
            identifier: String,
            iconPath: URL? = nil,
            minimumAPILevel: Int = 26,
            targetAPILevel: Int = 35,
            deepLinkSchemes: [String] = [],
            stripSourceMaps: Bool = true,
            stripExtensions: [String] = []
        )
    }
}
```

#### 3.1.3 `KSPackager.runAndroid(_:)` 구현 단계

1. **출력 디렉터리 준비**: `<output>/<App>-<version>-android/` 생성 (기존 삭제 후 재생성)
2. **Gradle 프로젝트 템플릿 복사**: 내장 템플릿(`Sources/KalsaeCLI/Support/Templates/AndroidApp/`)에서 복사
3. **settings.gradle.kts 업데이트**: `rootProject.name = "<App>"`
4. **app/build.gradle.kts 업데이트**:
   - `applicationId` → `identifier`
   - `versionCode` → 버전 해시 기반 정수
   - `versionName` → `version`
   - `minSdk` → `minimumAPILevel`
   - `targetSdk` → `targetAPILevel`
5. **AndroidManifest.xml 생성**:
   - `package` → `identifier`
   - `android:label` → `appName`
   - 딥링크 `intent-filter` (deepLinkSchemes 기반)
   - 인터넷 권한, POST_NOTIFICATIONS 권한
6. **Kalsae.json 복사 및 rewrite**:
   - `frontendDist` → `"assets"`
   - `devtools` → `false` (release 강제)
   - `devServerURL` → `"about:blank"` (release 차단)
7. **프론트엔드 dist 복사**: dist 내용 → `src/main/assets/` (인라인 복사)
8. **Strip 불필요 파일**: 소스맵 등 제거 (`KSBundleAnalyzer.strip`)
9. **Swift 공유 라이브러리 복사**: `libKalsaePlatformAndroid.so` → `src/main/jniLibs/arm64-v8a/`
10. **아이콘 생성**: 1024x1024 PNG 소스 → Android mipmap 리소스로 리사이즈
11. **strings.xml 생성**: `app_name` 리소스
12. **themes.xml 생성**: 기본 `Theme.KalsaeApp` (MaterialComponents DayNight 테마 상속)
13. **Gradle Wrapper 생성**: 내장 wrapper 파일 복사
14. **Report 반환**

#### 3.1.4 AndroidManifest.xml 템플릿

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="{identifier}">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:label="{appName}"
        android:supportsRtl="true"
        android:theme="@style/Theme.KalsaeApp"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|screenLayout|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
            {deepLinkIntentFilters}
        </activity>
    </application>
</manifest>
```

딥링크 intent-filter 템플릿:
```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="{scheme}" />
</intent-filter>
```

#### 3.1.5 아이콘 생성 전략

사용자가 `--icon`으로 1024x1024 PNG를 제공하면, 패키저가 `KSIconResizer` 유틸리티를 통해 다음 크기로 리사이즈하여 `res/mipmap-*/`에 배치한다:

| 디렉터리 | 파일명 | 크기 | density |
|---------|--------|------|---------|
| `mipmap-mdpi/` | `ic_launcher.png` / `ic_launcher_round.png` | 48×48 | mdpi (1x) |
| `mipmap-hdpi/` | `ic_launcher.png` / `ic_launcher_round.png` | 72×72 | hdpi (1.5x) |
| `mipmap-xhdpi/` | `ic_launcher.png` / `ic_launcher_round.png` | 96×96 | xhdpi (2x) |
| `mipmap-xxhdpi/` | `ic_launcher.png` / `ic_launcher_round.png` | 144×144 | xxhdpi (3x) |
| `mipmap-xxxhdpi/` | `ic_launcher.png` / `ic_launcher_round.png` | 192×192 | xxxhdpi (4x) |

`KSIconResizer`는 순수 Swift로 구현한다. `CGImage` + `CGContext`를 사용하여 1024x1024 PNG를 다양한 크기로 리사이즈한다. 외부 의존성 없음.

#### 3.1.6 Kotlin 템플릿 파일

**MainActivity.kt**:
```kotlin
package io.kalsae.app

import android.os.Bundle
import android.webkit.WebView
import androidx.appcompat.app.AppCompatActivity
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

class MainActivity : AppCompatActivity() {
    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        webView = WebView(this)
        setContentView(webView)

        // WebView 설정
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.allowFileAccess = true
        webView.settings.allowContentAccess = true

        // JNI 브리지 등록
        KalsaeJNI.registerEvaluateJs { js ->
            webView.evaluateJavascript(js, null)
        }
        KalsaeJNI.registerLoadUrl { url ->
            webView.loadUrl(url)
        }

        // JavaScript 인터페이스
        webView.addJavascriptInterface(
            WebAppInterface { json -> KalsaeJNI.onInboundMessage(json) },
            "__KS_bridge"
        )

        // Kalsae 시작
        KalsaeJNI.startup()

        // Document-start script 주입
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            KalsaeJNI.documentStartScript()?.let { script ->
                WebViewCompat.addDocumentStartJavaScript(webView, script, setOf("*"))
            }
        }

        // WebViewClient 설정 후 View Created 알림
        webView.webViewClient = object : android.webkit.WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                super.onPageStarted(view, url, favicon)
                KalsaeJNI.onViewCreated()
            }
        }

        // Kalsae 네비게이션 시작
        KalsaeJNI.navigate("ks://app/index.html")
    }

    override fun onResume() {
        super.onResume()
        KalsaeJNI.onResume()
    }

    override fun onPause() {
        super.onPause()
        KalsaeJNI.onPause()
    }
}
```

**KalsaeJNI.kt**:
```kotlin
package io.kalsae.app

object KalsaeJNI {
    init { System.loadLibrary("KalsaePlatformAndroid") }

    // C 함수 포인터 등록
    external fun KS_android_register_evaluate_js(fn: (String) -> Unit)
    external fun KS_android_register_load_url(fn: (String) -> Unit)

    // 수명 주기
    external fun KS_android_startup(): Int
    external fun KS_android_navigate(url: String)
    external fun KS_android_on_view_created()
    external fun KS_android_document_start_script(): String?
    external fun KS_android_free_string(ptr: String?)
    external fun KS_android_on_resume()
    external fun KS_android_on_pause()
    external fun KS_android_on_inbound_message(json: String)

    // Kotlin 래퍼
    fun registerEvaluateJs(fn: (String) -> Unit) = KS_android_register_evaluate_js(fn)
    fun registerLoadUrl(fn: (String) -> Unit) = KS_android_register_load_url(fn)
    fun startup(): Int = KS_android_startup()
    fun navigate(url: String) = KS_android_navigate(url)
    fun onViewCreated() = KS_android_on_view_created()
    fun documentStartScript(): String? = KS_android_document_start_script()
    fun onResume() = KS_android_on_resume()
    fun onPause() = KS_android_on_pause()
    fun onInboundMessage(json: String) = KS_android_on_inbound_message(json)
}
```

**WebAppInterface.kt**:
```kotlin
package io.kalsae.app

import android.webkit.JavascriptInterface

class WebAppInterface(
    private val onMessage: (String) -> Unit
) {
    @JavascriptInterface
    fun postMessage(json: String) {
        onMessage(json)
    }
}
```

#### 3.1.7 Gradle 템플릿

**app/build.gradle.kts**:
```kotlin
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "{identifier}"
    compileSdk = {targetAPILevel}

    defaultConfig {
        applicationId = "{identifier}"
        minSdk = {minimumAPILevel}
        targetSdk = {targetAPILevel}
        versionCode = {versionCode}
        versionName = "{version}"
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

    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.webkit)
}
```

**gradle/libs.versions.toml**:
```toml
[versions]
agp = "8.2.0"
kotlin = "1.9.20"
androidx-core = "1.12.0"
androidx-appcompat = "1.6.1"
androidx-webkit = "1.8.0"

[libraries]
androidx-core-ktx = { group = "androidx.core", name = "core-ktx", version.ref = "androidx-core" }
androidx-appcompat = { group = "androidx.appcompat", name = "appcompat", version.ref = "androidx-appcompat" }
androidx-webkit = { group = "androidx.webkit", name = "webkit", version.ref = "androidx-webkit" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
```

### 3.2 BuildCommand Android 분기

#### 3.2.1 `BuildCommand.swift` 수정

`runPackage(configuration:configURL:config:)` 메서드에 Android 분기 추가:

```swift
private func runPackage(configuration: String, configURL: URL, config: KSConfig) throws {
    let fm = FileManager.default
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
    let info = parseAppInfo(config: config)

    #if os(Windows)
        try runPackageWindows(...)
    #elseif os(macOS)
        // macOS 호스트에서 iOS/Android 패키징 지원
        if let target, target.lowercased().contains("android") {
            try runPackageAndroid(...)
        } else if let target, target.lowercased().contains("ios") {
            try runPackageIOS(...)
        } else {
            try runPackageMacOS(...)
        }
    #elseif os(Linux)
        // Linux 호스트에서 Android 패키징 지원
        if let target, target.lowercased().contains("android") {
            try runPackageAndroid(...)
        } else {
            print("⚠  Packaging is not supported on this host OS yet.")
        }
    #endif
}
```

#### 3.2.2 `runPackageAndroid` 구현

```swift
#if os(macOS) || os(Linux)
private func runPackageAndroid(
    configuration: String, configURL: URL,
    info: AppInfo, cwd: URL, fm: FileManager
) throws {
    // arch 검증: Android는 arm64만 허용
    let archLower = arch.lowercased()
    guard archLower == "arm64" else {
        throw ValidationError("Android packaging requires --arch arm64 (got '\(arch)')")
    }

    let buildDir = cwd.appendingPathComponent(".build/\(configuration)")
    // Android 크로스 컴파일 산출물: libKalsaePlatformAndroid.so
    let soName = "libKalsaePlatformAndroid.so"
    let exeURL = buildDir.appendingPathComponent(soName)
    guard fm.fileExists(atPath: exeURL.path) else {
        throw ValidationError(
            "Built shared library not found at \(exeURL.path). "
                + "Build with: swift build --target KalsaePlatformAndroid "
                + "--swift-sdk aarch64-unknown-linux-android26 -c release")
    }

    let distURL: URL? = {
        let resolved = KSBuildPlan.resolveDistURL(
            config: config, configURL: configURL, cwd: cwd, distOverride: dist)
        return fm.fileExists(atPath: resolved.path) ? resolved : nil
    }()

    let outputURL: URL = {
        if let o = output {
            return URL(fileURLWithPath: o, relativeTo: cwd)
        }
        return cwd.appendingPathComponent("dist/\(info.appName)-\(info.version)-android")
    }()
    try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let deepLinkSchemes: [String] = {
        guard let dl = config.deepLink else { return [] }
        return dl.schemes
    }()

    let opts = KSPackager.AndroidOptions(
        executablePath: exeURL,
        configPath: configURL,
        frontendDist: distURL,
        output: outputURL,
        appName: info.appName,
        version: info.version,
        identifier: info.identifier,
        iconPath: icon.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
        minimumAPILevel: 26,
        targetAPILevel: 35,
        deepLinkSchemes: deepLinkSchemes,
        stripSourceMaps: config.build.stripSourceMaps,
        stripExtensions: config.build.stripExtensions)

    print("📦  Packaging \(info.appName) v\(info.version) (Android)")
    let report = try KSPackager.runAndroid(opts)
    print(report.description)

    // Gradle APK 빌드 안내
    print("""
        ───────────────────────────────────────────────────────
        📱  Android project generated at:
            \(outputURL.path)

        To build the APK:
            cd \(outputURL.lastPathComponent)
            ./gradlew assembleRelease

        The APK will be at:
            app/build/outputs/apk/release/app-release.apk
        ───────────────────────────────────────────────────────
        """)
}
#endif
```

#### 3.2.3 CLI 옵션 확장

`BuildCommand`에 Android 관련 옵션 추가:
- `--target android` (Android 타겟 지정)
- `--arch arm64` (Android는 arm64만 허용, 검증 로직 추가)

### 3.3 Android PAL 안정화

#### 3.3.1 `KSAndroidDialogBackend` 기본 JNI 구현

현재 핸들러 주입형으로만 동작하지만, release를 위해 **기본 JNI 구현**을 제공한다:

**파일**: `Sources/KalsaePlatformAndroid/PAL/KSAndroidDialogBackend.swift`

변경 사항:
- `init()`에서 기본 핸들러를 자동 설치
- `onOpenFile` 기본값: JNI를 통한 `ActivityResultLauncher` (SAF) 호출
- `onMessage` 기본값: JNI를 통한 `AlertDialog` 표시
- `onSaveFile` 기본값: JNI를 통한 `ActivityResultLauncher` (SAF) 호출
- `onSelectFolder` 기본값: JNI를 통한 `ActivityResultLauncher` (SAF) 호출

```swift
public init() {
    // 기본 JNI 핸들러 설치
    self._onMessage = { [weak self] options, parent in
        guard let self else { return .ok }
        return await self.showAlertDialog(options: options)
    }
    self._onOpenFile = { [weak self] options, parent in
        guard let self else { return [] }
        return await self.pickFile(options: options)
    }
    // ...
}
```

JNI 훅을 통해 Kotlin `AlertDialog`와 `ActivityResultLauncher`를 호출한다. `KSAndroidJNI.swift`에 다음 C 함수 포인터를 추가:

```swift
@_cdecl("KS_android_register_show_alert")
public func KS_android_register_show_alert(
    _ fn: @convention(c) (UnsafePointer<CChar>, Int32) -> Int32
) {
    _hooksLock.withLock { _jniShowAlert = fn }
}
```

#### 3.3.2 `KSAndroidMenuBackend` PopupMenu 기반 구현

**파일**: `Sources/KalsaePlatformAndroid/PAL/KSAndroidMenuBackend.swift`

변경 사항:
- `showContextMenu`: Android `PopupMenu`를 JNI로 호출
- `installAppMenu`: Android에는 앱 메뉴 개념이 없으므로 no-op 유지 (문서화)
- `installWindowMenu`: Android에는 윈도우 메뉴 개념이 없으므로 no-op 유지 (문서화)

```swift
public func showContextMenu(
    _ items: [KSMenuItem],
    at point: KSPoint,
    in handle: KSWindowHandle?
) async throws(KSError) {
    guard let handler = lock.withLock({ _onShowContextMenu }) else {
        // 기본 no-op — throw하지 않고 조용히 무시
        return
    }
    try await handler(items, point, handle)
}
```

### 3.4 테스트 강화

#### 3.4.1 통합 테스트

**파일**: `Tests/KalsaePlatformAndroidTests/AndroidPALIntegrationTests.swift`

추가할 테스트:
- `KSAndroidWebViewHost` 실제 IPC 메시지 전송 검증 (모의 JNI 훅 사용)
- `KSAndroidDialogBackend` 기본 핸들러 동작 검증
- `KSAndroidDemoHost` 부트 시퀀스 검증
- `KSAndroidPlatform` config 기반 초기화 검증

#### 3.4.2 CI 파이프라인

`.github/workflows/`에 Android 크로스 컴파일 단계 추가:

```yaml
- name: Build Android shared library
  run: |
    swift build --target KalsaePlatformAndroid \
      --swift-sdk aarch64-unknown-linux-android26 \
      -c release
```

### 3.5 문서화

#### 3.5.1 README.md 업데이트

Android 플랫폼 상태를 "Preview"에서 "Stable"로 변경하고, Android 빌드 요구사항 추가.

#### 3.5.2 CLI.md 업데이트

Android 빌드 및 패키징 명령어 추가:

```bash
# Android 크로스 컴파일 (macOS/Linux 호스트)
swift build --target KalsaePlatformAndroid \
  --swift-sdk aarch64-unknown-linux-android26 \
  -c release

# Android 패키징
kalsae build --target android --arch arm64

# Android 패키징 (아이콘 포함)
kalsae build --target android --arch arm64 --icon ./AppIcon.png

# APK 빌드 (Gradle)
cd dist/MyApp-1.0.0-android/
./gradlew assembleRelease
```

---

## 4. 구현 계획

### Phase 1: Android 패키저 (예상: 4일)

| 작업 | 파일 | 설명 |
|------|------|------|
| 1.1 | `Sources/KalsaeCLI/Support/PackagerAndroid.swift` | `KSPackager.AndroidOptions` + `runAndroid(_:)` |
| 1.2 | `Sources/KalsaeCLI/Support/PackagerAndroid.swift` | AndroidManifest.xml 템플릿 생성 |
| 1.3 | `Sources/KalsaeCLI/Support/PackagerAndroid.swift` | 아이콘 리사이즈 + mipmap 배치 (`KSIconResizer`) |
| 1.4 | `Sources/KalsaeCLI/Support/PackagerAndroid.swift` | `rewritePackagedConfig` 호출 통합 |
| 1.5 | `Sources/KalsaeCLI/Support/Templates/AndroidApp/` | Gradle 프로젝트 템플릿 (build.gradle.kts, settings.gradle.kts, MainActivity.kt, KalsaeJNI.kt, WebAppInterface.kt, strings.xml, themes.xml, gradle wrapper) |
| 1.6 | `Sources/KalsaeCLI/Support/PackagerAndroid.swift` | Gradle wrapper 자동 복사 |

### Phase 2: BuildCommand Android 분기 (예상: 1일)

| 작업 | 파일 | 설명 |
|------|------|------|
| 2.1 | `Sources/KalsaeCLI/Commands/BuildCommand.swift` | `runPackageAndroid` 메서드 추가 |
| 2.2 | `Sources/KalsaeCLI/Commands/BuildCommand.swift` | Android `--arch` 검증 로직 (arm64 only) |
| 2.3 | `Sources/KalsaeCLI/Commands/BuildCommand.swift` | `--target android` 분기 처리 |

### Phase 3: Android PAL 안정화 (예상: 2일)

| 작업 | 파일 | 설명 |
|------|------|------|
| 3.1 | `Sources/KalsaePlatformAndroid/PAL/KSAndroidDialogBackend.swift` | 기본 JNI 핸들러 구현 (AlertDialog, SAF) |
| 3.2 | `Sources/KalsaePlatformAndroid/PAL/KSAndroidMenuBackend.swift` | PopupMenu 기반 컨텍스트 메뉴 |
| 3.3 | `Sources/KalsaePlatformAndroid/JNI/KSAndroidJNI.swift` | Dialog/메뉴용 JNI 훅 추가 |

### Phase 4: 테스트 강화 (예상: 2일)

| 작업 | 파일 | 설명 |
|------|------|------|
| 4.1 | `Tests/KalsaePlatformAndroidTests/AndroidPALIntegrationTests.swift` | 통합 테스트 추가 (IPC, Dialog, DemoHost) |
| 4.2 | `.github/workflows/` | Android 크로스 컴파일 CI 단계 추가 |

### Phase 5: 문서화 (예상: 0.5일)

| 작업 | 파일 | 설명 |
|------|------|------|
| 5.1 | `README.md` | Android 상태 "Preview" → "Stable" 업데이트 |
| 5.2 | `Docs/CLI.md` | Android 빌드/패키징 가이드 |

---

## 5. FAQ

### Q: Android 패키징이 macOS/Linux에서만 가능한 이유는?

Android NDK 크로스 컴파일은 Swift 6.0+에서 `--swift-sdk` 플래그로 지원된다. Windows에서도 Android NDK를 설정하면 가능하지만, 공식 지원은 macOS/Linux로 시작한다.

### Q: APK 빌드가 아닌 Gradle 프로젝트 생성인 이유는?

`kalsae build`는 Gradle 프로젝트를 생성하고, 실제 APK 빌드는 `./gradlew assembleRelease`로 위임한다. 이유는:
1. Gradle이 Android SDK/빌드 툴 체인의 복잡성을 관리
2. 사용자가 코드사이닝, ProGuard, 번들 포맷(AAB vs APK)을 자유롭게 설정 가능
3. 기존 Android 개발 워크플로와 호환

### Q: 아이콘 리사이즈에 외부 도구가 필요한가?

`KSIconResizer`는 순수 Swift로 구현한다. `CGImage` + `CGContext`를 사용하여 1024x1024 PNG를 Android mipmap 크기로 리사이즈한다. 외부 의존성 없음.

### Q: iOS와 Android release 전환의 차이점은?

| 항목 | iOS | Android |
|------|-----|---------|
| 패키지 포맷 | `.app` 번들 | Gradle 프로젝트 (APK는 Gradle 위임) |
| 크로스 컴파일 | macOS 전용 | macOS/Linux |
| `run()` | 지원 (UIKit main) | 영구 미지원 (Activity lifecycle) |
| Dialog 기본 구현 | UIKit (UIAlertController) | JNI → Kotlin (AlertDialog) |
| Menu 기본 구현 | UIMenu (iOS 16+) | PopupMenu (JNI) |
| 템플릿 필요 | Info.plist, LaunchScreen.storyboard | Gradle 프로젝트, AndroidManifest.xml |

### Q: Android에서 `kalsae dev`는 지원하는가?

Android 시뮬레이터/에뮬레이터에서는 `10.0.2.2`(호스트 루프백)를 통해 dev 서버에 접근할 수 있다. 하지만 현재 범위에서는 제외한다.

### Q: 기존 `Samples/KalsaeAndroidSample/`과의 관계는?

`Samples/KalsaeAndroidSample/`은 참조용 수동 샘플이다. `kalsae build --target android`는 내장 템플릿(`Sources/KalsaeCLI/Support/Templates/AndroidApp/`)을 기반으로 새 Gradle 프로젝트를 생성한다. 사용자는 필요에 따라 `Samples/KalsaeAndroidSample/`을 참고하여 템플릿을 커스터마이즈할 수 있다.

---

## 6. 변경 이력

| 날짜 | 변경 내용 |
|------|----------|
| 2026-05-09 | 초안 작성 |
