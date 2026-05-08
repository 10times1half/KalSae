#if os(Windows)
    import Testing
    import Foundation
    @testable import KalsaePlatformWindows

    // MARK: - WebView2 user-data 폴더 안전망
    //
    // `KSWebView2Runtime.resolve` 는 user-data 폴더를 절대 nil 로 두거나
    // `.build/` 트리 내부에 만들지 않아야 한다. 그렇지 않으면 WebView2 SDK 가
    // 기본값(EXE 옆 `<exeName>.WebView2`)을 사용해 `swift run` 동안
    // `msedgewebview2.exe` 들이 `.build/` 를 핸들로 잡아 빌드 산출물을
    // 지울 수 없게 된다.

    @Suite("KSWebView2Runtime — userDataFolder safety net")
    struct KSWebView2RuntimeTests {

        @Test("`.build/` 내부 EXE 디렉터리에서도 user-data 가 .build 밖으로 떨어진다")
        func userDataIsRedirectedAwayFromBuildTree() {
            let exeDir = URL(fileURLWithPath: "C:\\Projects\\Demo\\.build\\x86_64-unknown-windows-msvc\\debug")
            let resolved = KSWebView2Runtime.resolve(
                executableDir: exeDir, identifier: "demo")

            let folder = resolved.userDataFolder
            #expect(folder != nil, "userDataFolder must never be nil — WebView2 default would land in .build/")

            let normalized = folder!.replacingOccurrences(of: "/", with: "\\").lowercased()
            #expect(
                !normalized.contains("\\.build\\"),
                "userDataFolder must not be inside the project's `.build/` tree, got: \(folder!)")
        }

        @Test("`.build/` 외부 EXE 디렉터리에서는 LOCALAPPDATA 기반 경로를 사용한다")
        func userDataUsesLocalAppDataForRegularExeDir() {
            let exeDir = URL(fileURLWithPath: "C:\\Program Files\\Demo")
            let resolved = KSWebView2Runtime.resolve(
                executableDir: exeDir, identifier: "demo")

            let folder = resolved.userDataFolder
            #expect(folder != nil)
            // LOCALAPPDATA 가 설정된 일반적인 Windows 환경에서는 그 경로 안에
            // 위치해야 한다.
            if let local = ProcessInfo.processInfo.environment["LOCALAPPDATA"],
                !local.isEmpty
            {
                let lower = folder!.lowercased()
                #expect(
                    lower.hasPrefix(local.lowercased()),
                    "userDataFolder should sit under LOCALAPPDATA in non-.build EXE dirs, got: \(folder!)")
            }
        }

        @Test("isInsideBuildTree 는 정규화된 prefix 비교를 수행한다")
        func isInsideBuildTreeMatchesPaths() {
            let exeDir = URL(fileURLWithPath: "C:\\Projects\\Demo\\.build\\debug")

            #expect(
                KSWebView2Runtime.isInsideBuildTree(
                    path: "C:/Projects/Demo/.build/debug/demo.exe.WebView2",
                    executableDir: exeDir))
            #expect(
                KSWebView2Runtime.isInsideBuildTree(
                    path: "C:\\Projects\\Demo\\.build\\debug\\demo.exe.WebView2",
                    executableDir: exeDir))
            #expect(
                !KSWebView2Runtime.isInsideBuildTree(
                    path: "C:\\Users\\me\\AppData\\Local\\demo\\WebView2",
                    executableDir: exeDir))
        }

        @Test("fallbackUserDataDir 는 항상 비어있지 않은 절대 경로를 반환한다")
        func fallbackAlwaysReturnsAbsolutePath() {
            let path = KSWebView2Runtime.fallbackUserDataDir(identifier: "demo")
            #expect(!path.isEmpty)
            #expect(path.contains("Kalsae"))
            #expect(path.hasSuffix("WebView2"))
        }
    }
#endif
