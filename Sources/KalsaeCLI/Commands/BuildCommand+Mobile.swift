// MARK: - 모바일 패키징 (Android + iOS .app 번들)

import ArgumentParser
import Foundation
import KalsaeCLICore
import KalsaeCore

extension BuildCommand {
    /// Android Gradle 프로젝트 생성 (RFC-007). 호스트 OS 무관 (순수 파일 emit).
    /// 실제 APK 빌드는 호출자가 산출 디렉터리에서 `gradle wrapper` →
    /// `./gradlew assembleRelease` 로 수행한다.
    ///
    /// ## emit-only 설계 이유
    /// - Android SDK / NDK / Gradle 은 Windows/macOS/Linux 모두 설치 가능하지만,
    ///   크로스-컴파일된 `.so` 가 필요하므로 빌드 환경과 패키징을 분리했다.
    /// - 이 함수는 디스크에 완전한 Gradle 프로젝트 트리를 쓴다: root build.gradle.kts,
    ///   app/ module, Kotlin Activity 소스, mipmap icon 5종, AndroidManifest.xml,
    ///   jniLibs/arm64-v8a/ (사용자 제공 .so), kalsae.json 및 frontend dist 포함 assets/.
    ///
    /// ## 사용 예
    /// ```
    /// # 1. 네이티브 라이브러리 크로스 컴파일 (Linux or macOS, Swift 6.2 + Android SDK)
    /// swift build --swift-sdk aarch64-unknown-linux-android26 -c release \
    ///   --product KalsaePlatformAndroid
    /// # 2. 패키징 (어느 호스트에서나)
    /// kalsae build --android --android-native-lib .build/release/libKalsaePlatformAndroid.so
    /// # 3. APK 빌드 (Android SDK 필요)
    /// cd dist/android-MyApp-1.0/
    /// gradle wrapper ; ./gradlew assembleRelease
    /// ```
    func runPackageAndroid(
        config: KSConfig, info: AppInfo, cwd: URL, fm: FileManager
    ) throws {
        guard let libArg = androidNativeLib else {
            throw ValidationError(
                "--android requires --android-native-lib <path to libKalsaePlatformAndroid.so>. "
                    + "Build it first with: "
                    + "swift build --swift-sdk aarch64-unknown-linux-android\(androidMinSdk) "
                    + "-c release --product KalsaePlatformAndroid")
        }
        // Android 는 현재 arm64-v8a 만 지원한다. default(x64) 는 조용히 arm64 로 치환하고,
        // 사용자가 명시적으로 다른 값(`--arch arm64` 이외)을 지정한 경우에만 경고를 띄운다.
        if arch != "arm64" && arch != "x64" {
            print("⚠  --arch \(arch): Android currently supports only 'arm64' (arm64-v8a). Overriding to arm64.")
        }

        // 사용자 제공 `.so` 경로 — 빌드된 Android 네이티브 라이브러리.
        let libURL = URL(fileURLWithPath: libArg, relativeTo: cwd)
        let outputDir =
            output.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
            ?? cwd.appendingPathComponent("dist/android-\(info.appName)-\(info.version)")

        let applicationId = androidApplicationId ?? info.identifier
        let iconURL: URL? = androidIcon.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
        // 프론트엔드 dist: `--dist` CLI 인자가 우선, 없으면 `kalsae.json build.frontendDist` 사용.
        let frontendDistURL: URL? = {
            if let raw = dist, !raw.isEmpty {
                return URL(fileURLWithPath: raw, relativeTo: cwd)
            }
            let fallback = cwd.appendingPathComponent(config.build.frontendDist)
            return fm.fileExists(atPath: fallback.path) ? fallback : nil
        }()
        let deepLinkSchemes = config.deepLink?.schemes ?? []

        let opts = KSPackager.AndroidOptions(
            nativeLibPath: libURL,
            configPath: try resolveConfigURL(cwd: cwd, fm: fm),
            frontendDist: frontendDistURL,
            output: outputDir,
            appName: info.appName,
            version: info.version,
            identifier: applicationId,
            versionCode: androidVersionCode,
            minimumAPILevel: androidMinSdk,
            targetAPILevel: androidTargetSdk,
            architecture: .arm64,
            iconPath: iconURL,
            deepLinkSchemes: deepLinkSchemes)

        print("📦  Packaging \(info.appName) Android Gradle project v\(info.version) → \(outputDir.path)")
        if dryrun {
            print("   (dry-run: skipping file emission)")
            return
        }
        let report = try KSPackager.runAndroid(opts)
        print(report.description)
        print("ℹ  Next steps: cd '\(outputDir.path)' ; gradle wrapper ; ./gradlew assembleRelease")
    }

    /// Phase iOS-Stable §3 — `--ios` 플래그 진입점. 어느 호스트에서나 동작하는
    /// 미니멀 .app 번들 emit. 실제 디바이스 실행/시뮬레이터 설치는 macOS 가 필요.
    ///
    /// ## emit-only 설계 이유
    /// - iOS .app 번들은 XML plist + 디렉터리 구조로, Mach-O 바이너리만 있으면
    ///   Windows/macOS/Linux 어디서든 생성 가능하다.
    /// - Info.plist 에는 `NSAllowsArbitraryLoads=false` 가 설정되어 보안 기본값을 강제한다.
    /// - 실제 디바이스 실행/시뮬레이터 설치는 macOS + Xcode 필요:
    ///   `xcrun simctl install booted 'dist/ios-MyApp-1.0/MyApp.app'`
    ///
    /// ## `--store ios-appstore` 와의 차이
    /// `runPackageIOS()` 는 Xcode를 통해 실제 archive + IPA를 생성하는 반면,
    /// 이 함수는 호스트 무관 미니멀 .app 번들만 emit 한다 (App Store 제출 불가).
    func runPackageIOSAppBundle(
        config: KSConfig, info: AppInfo, cwd: URL, fm: FileManager
    ) throws {
        guard let exeArg = iosExecutable else {
            throw ValidationError(
                "--ios requires --ios-executable <path to iOS Mach-O binary>. "
                    + "Build it first with: "
                    + "swift build --triple arm64-apple-ios\(iosMinOSVersion) "
                    + "-c release --product <YourApp>")
        }
        let arch: KSPackager.IOSArchitecture = {
            switch self.arch {
            case "arm64", "x64": return .arm64
            case "arm64-simulator": return .arm64Simulator
            default:
                print(
                    "⚠  --arch \(self.arch): iOS supports 'arm64' or 'arm64-simulator'. "
                        + "Defaulting to arm64.")
                return .arm64
            }
        }()

        let exeURL = URL(fileURLWithPath: exeArg, relativeTo: cwd)
        let outputDir =
            output.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
            ?? cwd.appendingPathComponent("dist/ios-\(info.appName)-\(info.version)")

        let identifier = iosBundleIdentifier ?? info.identifier
        let iconURL: URL? = iosIcon.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
        let frontendDistURL: URL? = {
            if let raw = dist, !raw.isEmpty {
                return URL(fileURLWithPath: raw, relativeTo: cwd)
            }
            let fallback = cwd.appendingPathComponent(config.build.frontendDist)
            return fm.fileExists(atPath: fallback.path) ? fallback : nil
        }()
        let deepLinkSchemes = config.deepLink?.schemes ?? []

        let opts = KSPackager.IOSOptions(
            executablePath: exeURL,
            configPath: try resolveConfigURL(cwd: cwd, fm: fm),
            frontendDist: frontendDistURL,
            output: outputDir,
            appName: info.appName,
            version: info.version,
            identifier: identifier,
            bundleVersion: iosBundleVersion,
            minimumOSVersion: iosMinOSVersion,
            architecture: arch,
            iconPath: iconURL,
            deepLinkSchemes: deepLinkSchemes,
            permissions: config.permissions)

        print("📦  Packaging \(info.appName) iOS .app v\(info.version) → \(outputDir.path)")
        if dryrun {
            print("   (dry-run: skipping file emission)")
            return
        }
        let report = try KSPackager.runIOS(opts)
        print(report.description)
        print(
            "ℹ  Next steps: install on a simulator with "
                + "`xcrun simctl install booted '\(report.outputPath)'` "
                + "(macOS + Xcode required).")
    }
}
