/// Android Gradle 프로젝트 스캐폴드 패키저 (RFC-007 §3.1).
///
/// `swift build --swift-sdk aarch64-unknown-linux-android26 -c release` 로 빌드한
/// `libKalsaePlatformAndroid.so` 를 입력으로 받아, `gradle assembleRelease` 만
/// 호출하면 APK 가 나오는 완성된 Gradle 프로젝트 디렉터리를 생성한다.
///
/// 디렉터리 구조:
///   <output>/
///     app/
///       src/main/
///         AndroidManifest.xml
///         kotlin/<packagePath>/
///           MainActivity.kt
///           KalsaeJNI.kt
///           WebAppInterface.kt
///         res/values/{strings,themes}.xml
///         res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png
///         assets/  (Kalsae.json + frontend dist)
///         jniLibs/arm64-v8a/libKalsaePlatformAndroid.so
///       build.gradle.kts
///       proguard-rules.pro
///     build.gradle.kts
///     settings.gradle.kts
///     gradle.properties
///     gradle/libs.versions.toml
///
/// Gradle Wrapper 는 binary 라 본 패키저에서 emit 하지 않는다. 호출자는
/// `output` 디렉터리에서 `gradle wrapper` 를 1회 실행하거나 IDE 로 import 한다.
/// 그 후 `./gradlew assembleRelease` → `app/build/outputs/apk/release/app-release.apk`.
///
/// 본 패키저는 어느 호스트 OS 에서도 실행 가능하다 (순수 파일 emit). 실제
/// Android 크로스 컴파일은 Linux/macOS 호스트에서 Android Swift SDK 로 수행한다.
public import Foundation
internal import KalsaeCore

extension KSPackager {

    public enum AndroidArchitecture: String, Sendable, CaseIterable {
        case arm64 = "arm64-v8a"
        // 향후 확장 (x86_64 emulator) — 현재 RFC-007 은 arm64 만 명시.
    }

    public struct AndroidOptions: Sendable {
        /// 빌드된 네이티브 라이브러리 경로 (`libKalsaePlatformAndroid.so`).
        public var nativeLibPath: URL
        /// 원본 Kalsae.json 경로 (assets/ 로 복사 + rewrite).
        public var configPath: URL
        /// 프론트엔드 dist 디렉터리. nil 이거나 미존재 시 경고만.
        public var frontendDist: URL?
        /// 결과 Gradle 프로젝트가 위치할 디렉터리 (`dist/android-<App>-<ver>/`).
        public var output: URL
        public var appName: String
        public var version: String
        /// 패키지 식별자 (`com.example.myapp`). Android applicationId 로 사용.
        public var identifier: String
        public var versionCode: Int
        public var minimumAPILevel: Int
        public var targetAPILevel: Int
        public var architecture: AndroidArchitecture
        /// 아이콘 PNG. 1024 권장. nil 이면 placeholder (단색 PNG) 생성.
        public var iconPath: URL?
        /// 딥 링크 스킴들 (Kalsae.json `deepLink.schemes`). 비어있으면 intent-filter 생략.
        public var deepLinkSchemes: [String]
        /// 패키징 시 소스맵(.map) 등 자동 제거.
        public var stripSourceMaps: Bool
        public var stripExtensions: [String]

        public init(
            nativeLibPath: URL,
            configPath: URL,
            frontendDist: URL?,
            output: URL,
            appName: String,
            version: String,
            identifier: String,
            versionCode: Int = 1,
            minimumAPILevel: Int = 26,
            targetAPILevel: Int = 35,
            architecture: AndroidArchitecture = .arm64,
            iconPath: URL? = nil,
            deepLinkSchemes: [String] = [],
            stripSourceMaps: Bool = true,
            stripExtensions: [String] = []
        ) {
            self.nativeLibPath = nativeLibPath
            self.configPath = configPath
            self.frontendDist = frontendDist
            self.output = output
            self.appName = appName
            self.version = version
            self.identifier = identifier
            self.versionCode = versionCode
            self.minimumAPILevel = minimumAPILevel
            self.targetAPILevel = targetAPILevel
            self.architecture = architecture
            self.iconPath = iconPath
            self.deepLinkSchemes = deepLinkSchemes
            self.stripSourceMaps = stripSourceMaps
            self.stripExtensions = stripExtensions
        }
    }

    // MARK: - 메인 진입점

    public static func runAndroid(_ opts: AndroidOptions) throws -> Report {
        let fm = FileManager.default
        var warnings: [String] = []

        // 0) 사전 검증
        guard fm.fileExists(atPath: opts.nativeLibPath.path) else {
            throw KSError(
                code: .configInvalid,
                message: "Android native library not found at \(opts.nativeLibPath.path). "
                    + "Build it first with: "
                    + "swift build --swift-sdk aarch64-unknown-linux-android\(opts.minimumAPILevel) "
                    + "-c release --product KalsaePlatformAndroid")
        }
        guard isValidPackageIdentifier(opts.identifier) else {
            throw KSError(
                code: .configInvalid,
                message: "Android applicationId '\(opts.identifier)' is invalid. "
                    + "Must match: ^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$")
        }
        guard opts.minimumAPILevel >= 26 else {
            throw KSError(
                code: .configInvalid,
                message: "Android minimumAPILevel must be >= 26 (got \(opts.minimumAPILevel)).")
        }
        guard opts.targetAPILevel >= opts.minimumAPILevel else {
            throw KSError(
                code: .configInvalid,
                message: "Android targetAPILevel (\(opts.targetAPILevel)) must be "
                    + ">= minimumAPILevel (\(opts.minimumAPILevel)).")
        }

        // 1) 출력 디렉터리 (clean rebuild)
        if fm.fileExists(atPath: opts.output.path) {
            try retryingTransient { try fm.removeItem(at: opts.output) }
        }
        try fm.createDirectory(at: opts.output, withIntermediateDirectories: true)

        let app = opts.output.appendingPathComponent("app")
        let srcMain = app.appendingPathComponent("src/main")
        let resValues = srcMain.appendingPathComponent("res/values")
        let assets = srcMain.appendingPathComponent("assets")
        let jniLibs = srcMain.appendingPathComponent("jniLibs")
            .appendingPathComponent(opts.architecture.rawValue)
        try fm.createDirectory(at: srcMain, withIntermediateDirectories: true)
        try fm.createDirectory(at: resValues, withIntermediateDirectories: true)
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        try fm.createDirectory(at: jniLibs, withIntermediateDirectories: true)

        // 2) 루트 Gradle 파일
        try renderRootBuildGradle().write(
            to: opts.output.appendingPathComponent("build.gradle.kts"),
            atomically: true, encoding: .utf8)
        try renderSettingsGradle(appName: opts.appName).write(
            to: opts.output.appendingPathComponent("settings.gradle.kts"),
            atomically: true, encoding: .utf8)
        try renderGradleProperties().write(
            to: opts.output.appendingPathComponent("gradle.properties"),
            atomically: true, encoding: .utf8)
        let versionsDir = opts.output.appendingPathComponent("gradle")
        try fm.createDirectory(at: versionsDir, withIntermediateDirectories: true)
        try renderLibsVersionsToml().write(
            to: versionsDir.appendingPathComponent("libs.versions.toml"),
            atomically: true, encoding: .utf8)

        // 3) app/build.gradle.kts + proguard
        try renderAppBuildGradle(opts: opts).write(
            to: app.appendingPathComponent("build.gradle.kts"),
            atomically: true, encoding: .utf8)
        try renderProguardRules().write(
            to: app.appendingPathComponent("proguard-rules.pro"),
            atomically: true, encoding: .utf8)

        // 4) AndroidManifest.xml
        try renderAndroidManifest(opts: opts).write(
            to: srcMain.appendingPathComponent("AndroidManifest.xml"),
            atomically: true, encoding: .utf8)

        // 5) Kotlin 소스
        let packagePath = opts.identifier.replacingOccurrences(of: ".", with: "/")
        let kotlinDir = srcMain.appendingPathComponent("kotlin").appendingPathComponent(packagePath)
        try fm.createDirectory(at: kotlinDir, withIntermediateDirectories: true)
        try renderMainActivityKt(identifier: opts.identifier).write(
            to: kotlinDir.appendingPathComponent("MainActivity.kt"),
            atomically: true, encoding: .utf8)
        try renderKalsaeJNIKt(identifier: opts.identifier).write(
            to: kotlinDir.appendingPathComponent("KalsaeJNI.kt"),
            atomically: true, encoding: .utf8)
        try renderWebAppInterfaceKt(identifier: opts.identifier).write(
            to: kotlinDir.appendingPathComponent("WebAppInterface.kt"),
            atomically: true, encoding: .utf8)

        // 6) 리소스 (strings, themes, mipmaps)
        try renderStringsXml(appName: opts.appName).write(
            to: resValues.appendingPathComponent("strings.xml"),
            atomically: true, encoding: .utf8)
        try renderThemesXml().write(
            to: resValues.appendingPathComponent("themes.xml"),
            atomically: true, encoding: .utf8)
        let iconWarnings = try emitMipmaps(
            sourceIcon: opts.iconPath, resRoot: srcMain.appendingPathComponent("res"), fm: fm)
        warnings.append(contentsOf: iconWarnings)

        // 7) Kalsae.json (assets/) — frontendDist 를 "." 으로 rewrite + devtools off
        let dstConfig = assets.appendingPathComponent("Kalsae.json")
        try safeCopy(from: opts.configPath, to: dstConfig, fm: fm)
        try rewritePackagedConfig(at: dstConfig, frontendDist: ".", disableDevtools: true)

        // 8) Frontend dist → assets/
        if let dist = opts.frontendDist, fm.fileExists(atPath: dist.path) {
            try copyDistContents(of: dist, into: assets, fm: fm)
            let strip = KSBundleAnalyzer.strip(
                distURL: assets,
                stripSourceMaps: opts.stripSourceMaps,
                stripExtensions: opts.stripExtensions)
            if strip.removed > 0 {
                print(
                    "  🗑  Stripped \(strip.removed) file(s) "
                        + "(\(KSBundleReport.formatBytes(strip.savedBytes)))")
            }
            if strip.failed > 0 {
                warnings.append(
                    "Failed to strip \(strip.failed) file(s) from frontend bundle.")
            }
        } else {
            warnings.append(
                "Frontend dist directory not found; APK will have no web assets in assets/.")
        }

        // 9) 네이티브 라이브러리
        let dstLib = jniLibs.appendingPathComponent("libKalsaePlatformAndroid.so")
        try safeCopy(from: opts.nativeLibPath, to: dstLib, fm: fm)

        // 10) 안내 README
        try renderProjectReadme(opts: opts).write(
            to: opts.output.appendingPathComponent("README.md"),
            atomically: true, encoding: .utf8)

        return Report(
            outputPath: opts.output.path,
            zipPath: nil,
            policy: "android-gradle",
            warnings: warnings,
            standalone: nil)
    }

    // MARK: - 검증

    /// Android `applicationId` 규칙: 마침표로 구분된 2개 이상의 세그먼트.
    /// 각 세그먼트는 소문자 영문자로 시작, 소문자/숫자/언더스코어.
    static func isValidPackageIdentifier(_ id: String) -> Bool {
        let segments = id.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        for seg in segments {
            guard let first = seg.first, first.isLetter, first.isLowercase else { return false }
            for ch in seg {
                if ch.isLetter && ch.isLowercase { continue }
                if ch.isNumber { continue }
                if ch == "_" { continue }
                return false
            }
        }
        return true
    }

    // MARK: - 파일 emit (Gradle/Kotlin/XML 모두 인라인 문자열)

    static func renderRootBuildGradle() -> String {
        """
        // 루트 build.gradle.kts — Kalsae generated.
        plugins {
            alias(libs.plugins.android.application) apply false
            alias(libs.plugins.kotlin.android) apply false
        }
        """
    }

    static func renderSettingsGradle(appName: String) -> String {
        // appName 은 Gradle rootProject.name 으로 사용. 공백/특수문자 escape.
        let safe = appName.replacingOccurrences(of: "\"", with: "\\\"")
        return """
            // settings.gradle.kts — Kalsae generated.
            pluginManagement {
                repositories {
                    google()
                    mavenCentral()
                    gradlePluginPortal()
                }
            }
            dependencyResolutionManagement {
                repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
                repositories {
                    google()
                    mavenCentral()
                }
            }
            rootProject.name = "\(safe)"
            include(":app")
            """
    }

    static func renderGradleProperties() -> String {
        """
        # Kalsae generated.
        org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
        android.useAndroidX=true
        android.nonTransitiveRClass=true
        kotlin.code.style=official
        """
    }

    static func renderLibsVersionsToml() -> String {
        """
        # Kalsae generated — pinned versions for Android builds (RFC-007).
        [versions]
        agp = "8.6.0"
        kotlin = "2.0.20"
        androidx-core = "1.13.1"
        androidx-appcompat = "1.7.0"
        androidx-webkit = "1.11.0"
        material = "1.12.0"

        [libraries]
        androidx-core-ktx = { module = "androidx.core:core-ktx", version.ref = "androidx-core" }
        androidx-appcompat = { module = "androidx.appcompat:appcompat", version.ref = "androidx-appcompat" }
        androidx-webkit = { module = "androidx.webkit:webkit", version.ref = "androidx-webkit" }
        material = { module = "com.google.android.material:material", version.ref = "material" }

        [plugins]
        android-application = { id = "com.android.application", version.ref = "agp" }
        kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
        """
    }

    static func renderAppBuildGradle(opts: AndroidOptions) -> String {
        """
        // app/build.gradle.kts — Kalsae generated.
        plugins {
            alias(libs.plugins.android.application)
            alias(libs.plugins.kotlin.android)
        }

        android {
            namespace = "\(opts.identifier)"
            compileSdk = \(opts.targetAPILevel)

            defaultConfig {
                applicationId = "\(opts.identifier)"
                minSdk = \(opts.minimumAPILevel)
                targetSdk = \(opts.targetAPILevel)
                versionCode = \(opts.versionCode)
                versionName = "\(opts.version)"

                ndk {
                    abiFilters += listOf("\(opts.architecture.rawValue)")
                }
            }

            buildTypes {
                release {
                    isMinifyEnabled = true
                    proguardFiles(
                        getDefaultProguardFile("proguard-android-optimize.txt"),
                        "proguard-rules.pro"
                    )
                }
                debug {
                    isMinifyEnabled = false
                }
            }

            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
            kotlinOptions {
                jvmTarget = "17"
            }

            sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")
            sourceSets["main"].assets.srcDirs("src/main/assets")
        }

        dependencies {
            implementation(libs.androidx.core.ktx)
            implementation(libs.androidx.appcompat)
            implementation(libs.androidx.webkit)
            implementation(libs.material)
        }
        """
    }

    static func renderProguardRules() -> String {
        """
        # Kalsae generated proguard rules.
        # Keep JNI entry points and registration callbacks.
        -keep class * {
            @android.webkit.JavascriptInterface <methods>;
        }
        -keepclasseswithmembernames class * {
            native <methods>;
        }
        """
    }

    static func renderAndroidManifest(opts: AndroidOptions) -> String {
        var intentFilters = ""
        // 표준 LAUNCHER intent-filter
        intentFilters += """
                    <intent-filter>
                        <action android:name="android.intent.action.MAIN" />
                        <category android:name="android.intent.category.LAUNCHER" />
                    </intent-filter>
            """
        // 딥링크 스킴이 있으면 VIEW intent-filter 추가
        for scheme in opts.deepLinkSchemes
        where !scheme.isEmpty && scheme.range(of: "^[a-z][a-z0-9+.-]*$", options: .regularExpression) != nil {
            intentFilters += """

                    <intent-filter android:autoVerify="false">
                        <action android:name="android.intent.action.VIEW" />
                        <category android:name="android.intent.category.DEFAULT" />
                        <category android:name="android.intent.category.BROWSABLE" />
                        <data android:scheme="\(scheme)" />
                    </intent-filter>
            """
        }
        return """
            <?xml version="1.0" encoding="utf-8"?>
            <manifest xmlns:android="http://schemas.android.com/apk/res/android">

                <uses-permission android:name="android.permission.INTERNET" />

                <application
                    android:allowBackup="true"
                    android:icon="@mipmap/ic_launcher"
                    android:label="@string/app_name"
                    android:supportsRtl="true"
                    android:theme="@style/Theme.KalsaeApp">

                    <activity
                        android:name=".MainActivity"
                        android:exported="true"
                        android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout|keyboard|keyboardHidden|navigation"
                        android:launchMode="singleTask">
            \(intentFilters)
                    </activity>
                </application>
            </manifest>
            """
    }

    static func renderMainActivityKt(identifier: String) -> String {
        """
        package \(identifier)

        import android.os.Bundle
        import android.webkit.WebView
        import android.webkit.WebViewClient
        import androidx.appcompat.app.AppCompatActivity
        import androidx.webkit.WebViewCompat
        import androidx.webkit.WebViewFeature

        class MainActivity : AppCompatActivity() {

            private lateinit var webView: WebView

            override fun onCreate(savedInstanceState: Bundle?) {
                super.onCreate(savedInstanceState)

                // 1. JNI 훅을 모두 등록한 후 startup 호출
                KalsaeJNI.installAll(this) { js -> webView.evaluateJavascript(js, null) }

                // 2. Swift 런타임 초기화
                val rc = KalsaeJNI.startup()
                if (rc != 0) {
                    finish()
                    return
                }

                // 3. WebView 생성 + 설정
                webView = WebView(this)
                webView.settings.javaScriptEnabled = true
                webView.settings.domStorageEnabled = true
                webView.webViewClient = WebViewClient()
                webView.addJavascriptInterface(WebAppInterface(), "__ks_native")

                // 4. document-start 스크립트 주입
                if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                    val script = KalsaeJNI.documentStartScript()
                    if (script != null) {
                        WebViewCompat.addDocumentStartJavaScript(webView, script, setOf("*"))
                    }
                }

                setContentView(webView)
                KalsaeJNI.onViewCreated()

                // 5. 초기 URL 로딩 (assets/ 의 index.html)
                webView.loadUrl("file:///android_asset/index.html")
            }

            override fun onResume() {
                super.onResume()
                KalsaeJNI.onResume()
            }

            override fun onPause() {
                KalsaeJNI.onPause()
                super.onPause()
            }
        }
        """
    }

    static func renderKalsaeJNIKt(identifier: String) -> String {
        """
        package \(identifier)

        import android.content.Context
        import android.webkit.WebView

        /// Swift 런타임(`libKalsaePlatformAndroid.so`) 으로의 JNI 브리지.
        /// `MainActivity.onCreate` 에서 `installAll(...)` → `startup()` 순서로 호출.
        object KalsaeJNI {

            init {
                System.loadLibrary("KalsaePlatformAndroid")
            }

            // MARK: - native exports

            external fun startup(): Int
            external fun navigate(url: String)
            external fun onViewCreated()
            external fun documentStartScript(): String?
            external fun freeString(ptr: Long)
            external fun onInboundMessage(json: String)
            external fun onResume()
            external fun onPause()

            // MARK: - 호스트 측에서 Swift 로 등록하는 콜백들

            fun installAll(context: Context, evaluateJs: (String) -> Unit) {
                registerEvaluateJs(evaluateJs)
                registerLoadUrl { url -> /* 호출자가 WebView 주입 필요 시 override */ }
            }

            external fun registerEvaluateJs(fn: (String) -> Unit)
            external fun registerLoadUrl(fn: (String) -> Unit)

            // RFC-007 Phase 4 (scaffolding) — Dialog/Menu 훅 등록.
            // Kotlin 호스트가 AlertDialog / ActivityResultLauncher / PopupMenu
            // 어댑터를 주입할 수 있도록 register 진입점을 노출한다.
            // 사용자 응답은 `onDialogResult(requestId, resultJson)` 으로 되돌린다.
            external fun registerShowAlert(fn: (Int, String) -> Unit)
            external fun registerPickFile(fn: (Int, String) -> Unit)
            external fun registerSaveFile(fn: (Int, String) -> Unit)
            external fun registerSelectFolder(fn: (Int, String) -> Unit)
            external fun registerShowContextMenu(fn: (Int, String, Int, Int) -> Unit)

            /// 다이얼로그/파일 선택 결과를 Swift 로 되돌린다.
            ///
            /// 결과 JSON 형식:
            ///   - openFile     : `{"urls":["file:///..."]}` (취소 시 빈 배열)
            ///   - saveFile     : `{"url":"file:///..."}`    (취소 시 `"url":null` 또는 생략)
            ///   - selectFolder : `{"url":"file:///..."}`
            ///   - message      : `{"result":"ok"|"cancel"|"yes"|"no"}`
            external fun onDialogResult(requestId: Int, resultJson: String)
        }
        """
    }

    static func renderWebAppInterfaceKt(identifier: String) -> String {
        """
        package \(identifier)

        import android.webkit.JavascriptInterface

        /// JS → Swift 인바운드 메시지 통로. `__ks_native.postMessage(...)` 로 호출됨.
        class WebAppInterface {
            @JavascriptInterface
            fun postMessage(json: String) {
                KalsaeJNI.onInboundMessage(json)
            }
        }
        """
    }

    static func renderStringsXml(appName: String) -> String {
        let escaped = appName
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
            <?xml version="1.0" encoding="utf-8"?>
            <resources>
                <string name="app_name">\(escaped)</string>
            </resources>
            """
    }

    static func renderThemesXml() -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <resources xmlns:tools="http://schemas.android.com/tools">
            <style name="Theme.KalsaeApp" parent="Theme.Material3.DayNight.NoActionBar">
                <item name="android:statusBarColor" tools:targetApi="l">?attr/colorPrimaryVariant</item>
            </style>
        </resources>
        """
    }

    static func renderProjectReadme(opts: AndroidOptions) -> String {
        """
        # \(opts.appName) — Android Gradle Project

        Kalsae 가 생성한 Android Gradle 프로젝트. APK 빌드 절차:

        ## 1. Gradle Wrapper 1회 설치 (최초 1회만)

            cd "\(opts.output.lastPathComponent)"
            gradle wrapper --gradle-version 8.10

        호스트에 `gradle` 이 없으면 Android Studio 로 디렉터리를 import 해도 된다.

        ## 2. 디버그 / 릴리스 APK 빌드

            ./gradlew assembleDebug
            ./gradlew assembleRelease

        산출물: `app/build/outputs/apk/{debug,release}/app-{debug,release}.apk`

        ## 3. 디바이스 설치

            adb install -r app/build/outputs/apk/release/app-release.apk

        ## 메타데이터

        - applicationId: `\(opts.identifier)`
        - versionName / versionCode: `\(opts.version)` / `\(opts.versionCode)`
        - minSdk / targetSdk: `\(opts.minimumAPILevel)` / `\(opts.targetAPILevel)`
        - ABI: `\(opts.architecture.rawValue)`
        """
    }

    // MARK: - frontend dist 복사 (PackagerMac.copyContents 와 동일 패턴)

    private static func copyDistContents(of src: URL, into dst: URL, fm: FileManager) throws {
        let items = try fm.contentsOfDirectory(
            at: src, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for item in items {
            let target = dst.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try safeCopy(from: item, to: target, fm: fm)
        }
    }

    // MARK: - mipmap PNG emit

    /// 5개 mipmap 디렉터리에 ic_launcher.png 를 배치한다.
    /// `sourceIcon` 이 nil 이면 placeholder PNG 를 생성.
    /// CoreGraphics 가 없는 호스트(Windows/Linux) 에서는 원본을 그대로 5개에 복사한다
    /// (Android 가 런타임에 mipmap 셀렉션을 수행하므로 동작은 보장됨).
    private static func emitMipmaps(
        sourceIcon: URL?, resRoot: URL, fm: FileManager
    ) throws -> [String] {
        var warnings: [String] = []
        let densities: [(String, Int)] = [
            ("mipmap-mdpi", 48),
            ("mipmap-hdpi", 72),
            ("mipmap-xhdpi", 96),
            ("mipmap-xxhdpi", 144),
            ("mipmap-xxxhdpi", 192),
        ]
        for (dir, _) in densities {
            try fm.createDirectory(
                at: resRoot.appendingPathComponent(dir), withIntermediateDirectories: true)
        }

        let iconData: Data
        if let src = sourceIcon, fm.fileExists(atPath: src.path) {
            iconData = try Data(contentsOf: src)
        } else {
            iconData = KSIconResizer.placeholderPNG()
            warnings.append(
                "No icon supplied — using a 1x1 placeholder PNG for all mipmap densities.")
        }

        for (dir, size) in densities {
            let dst = resRoot.appendingPathComponent(dir).appendingPathComponent("ic_launcher.png")
            let resized = KSIconResizer.resizeIfPossible(pngData: iconData, to: size)
            try resized.write(to: dst, options: [.atomic])
        }
        if !KSIconResizer.isResizingSupported {
            warnings.append(
                "Icon resizing requires CoreGraphics (macOS/iOS host). On this host the source "
                    + "image is copied unchanged into all 5 mipmap densities — Android scales at "
                    + "runtime, so the APK still works but on-disk PNG sizes are not density-accurate.")
        }
        return warnings
    }
}
