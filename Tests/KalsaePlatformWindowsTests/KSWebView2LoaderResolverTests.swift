#if os(Windows)
    import Testing
    import Foundation
    @testable import KalsaePlatformWindows

    // MARK: - WebView2 loader 검색 경로 결정 로직
    //
    // `KSWebView2LoaderResolver.locateLoaderDirectory` 는 EXE 디렉터리에 DLL 이
    // 없을 경우 `.build/checkouts/<KalSae*>/Sources/CKalsaeWV2/Vendor/WebView2/
    // runtimes/<arch>/native/` 에서 fallback 으로 찾아야 한다. 이 스위트는
    // 임시 디렉터리에 가짜 SwiftPM 트리를 만들어 후보 결정 결과를 검증한다.

    @Suite("KSWebView2LoaderResolver — locateLoaderDirectory")
    struct KSWebView2LoaderResolverTests {

        private static var arch: String {
            #if arch(arm64)
                return "win-arm64"
            #else
                return "win-x64"
            #endif
        }

        private func makeTempRoot() throws -> URL {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("KSWV2LoaderResolver-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true)
            return root
        }

        @Test("EXE 디렉터리에 DLL 이 있으면 그 경로를 우선 반환한다")
        func returnsExeDirectoryWhenDLLPresent() throws {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }

            let exeDir = root.appendingPathComponent("bin")
            try FileManager.default.createDirectory(
                at: exeDir, withIntermediateDirectories: true)
            let dll = exeDir.appendingPathComponent("WebView2Loader.dll")
            try Data().write(to: dll)

            let resolved = KSWebView2LoaderResolver.locateLoaderDirectory(
                executableDir: exeDir)
            #expect(resolved == exeDir.path)
        }

        @Test(".build/checkouts/<KalSae>/.../native 에 DLL 이 있으면 fallback 으로 반환한다")
        func returnsCheckoutsFallback() throws {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }

            // SwiftPM 레이아웃: <root>/.build/<triple>/debug/<exe>
            let exeDir =
                root
                .appendingPathComponent(".build")
                .appendingPathComponent("x86_64-unknown-windows-msvc")
                .appendingPathComponent("debug")
            try FileManager.default.createDirectory(
                at: exeDir, withIntermediateDirectories: true)

            // checkouts/KalSae/Sources/CKalsaeWV2/Vendor/WebView2/runtimes/<arch>/native/WebView2Loader.dll
            let nativeDir =
                root
                .appendingPathComponent(".build")
                .appendingPathComponent("checkouts")
                .appendingPathComponent("KalSae")
                .appendingPathComponent("Sources")
                .appendingPathComponent("CKalsaeWV2")
                .appendingPathComponent("Vendor")
                .appendingPathComponent("WebView2")
                .appendingPathComponent("runtimes")
                .appendingPathComponent(Self.arch)
                .appendingPathComponent("native")
            try FileManager.default.createDirectory(
                at: nativeDir, withIntermediateDirectories: true)
            try Data().write(
                to: nativeDir.appendingPathComponent("WebView2Loader.dll"))

            let resolved = KSWebView2LoaderResolver.locateLoaderDirectory(
                executableDir: exeDir)
            #expect(resolved == nativeDir.path)
        }

        @Test("어디에도 DLL 이 없으면 nil 을 반환한다")
        func returnsNilWhenAbsent() throws {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }

            let exeDir = root.appendingPathComponent("bin")
            try FileManager.default.createDirectory(
                at: exeDir, withIntermediateDirectories: true)

            let resolved = KSWebView2LoaderResolver.locateLoaderDirectory(
                executableDir: exeDir)
            #expect(resolved == nil)
        }

        @Test("checkouts 디렉터리 이름이 KalSae 변형(대소문자)이어도 매칭된다")
        func matchesCaseInsensitiveCheckoutName() throws {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }

            let exeDir =
                root
                .appendingPathComponent(".build")
                .appendingPathComponent("debug")
            try FileManager.default.createDirectory(
                at: exeDir, withIntermediateDirectories: true)

            let nativeDir =
                root
                .appendingPathComponent(".build")
                .appendingPathComponent("checkouts")
                .appendingPathComponent("kalsae")  // 소문자
                .appendingPathComponent("Sources")
                .appendingPathComponent("CKalsaeWV2")
                .appendingPathComponent("Vendor")
                .appendingPathComponent("WebView2")
                .appendingPathComponent("runtimes")
                .appendingPathComponent(Self.arch)
                .appendingPathComponent("native")
            try FileManager.default.createDirectory(
                at: nativeDir, withIntermediateDirectories: true)
            try Data().write(
                to: nativeDir.appendingPathComponent("WebView2Loader.dll"))

            let resolved = KSWebView2LoaderResolver.locateLoaderDirectory(
                executableDir: exeDir)
            #expect(resolved == nativeDir.path)
        }
    }
#endif
