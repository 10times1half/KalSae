#if os(Windows)
    internal import Foundation
    internal import CKalsaeWV2
    internal import KalsaeCore

    /// `WebView2Loader.dll` 의 실제 검색 경로를 `LoadLibraryW` 보다 먼저
    /// 결정한다.
    ///
    /// `kalsae build` 가 만든 패키지 산출물에서는 EXE 디렉터리에 DLL 이 같이
    /// 들어 있어 자연스럽게 로드된다. 그러나 컨슈머가 `swift build` /
    /// `swift run` 으로 직접 빌드할 때 EXE 는
    /// `.build/<triple>/debug/<name>.exe` 에 생기지만, DLL 은 SDK 체크아웃
    /// (`.build/checkouts/<KalSae>/Sources/CKalsaeWV2/Vendor/WebView2/...`)
    /// 안에만 있어 `LoadLibraryW("WebView2Loader.dll")` 가
    /// `0x8007007E (ERROR_MOD_NOT_FOUND)` 로 실패한다.
    ///
    /// 이 헬퍼는 다음 순서로 디렉터리를 검사하고, 첫 번째로
    /// `WebView2Loader.dll` 이 존재하는 디렉터리를
    /// `KSWV2_SetLoaderSearchDirectory` 에 등록한다.
    ///
    /// 1. 실행 파일 디렉터리 (정상 동작 케이스).
    /// 2. `.build/checkouts/<KalSae*>/Sources/CKalsaeWV2/Vendor/WebView2/`
    ///    `runtimes/<arch>/native/` — `swift build` 직접 사용 시.
    ///
    /// 첫 `KSWV2_CreateEnvironment` 호출 이전에만 효과가 있으므로
    /// `WebView2Host.createEnvironmentSync` 의 진입부에서 호출한다.
    internal enum KSWebView2LoaderResolver {
        /// `nonisolated(unsafe)` 정적 변수 대신 `NSLock`로 보호되는 공유 상태.
        /// `KSCommandRegistry`와 동일한 `final class @unchecked Sendable` 패턴을 사용하여
        /// Swift 6 strict concurrency 검사에 안전하게 한 번만 초기화한다.
        private final class State: @unchecked Sendable {
            private let lock = NSLock()
            private var didEnsure: Bool = false

            /// `work`는 최초 1회만 실행된다. InitOnce semantics를 가진다.
            func ensureOnce(_ work: () -> Void) {
                lock.lock()
                let already = didEnsure
                didEnsure = true
                lock.unlock()
                if !already { work() }
            }
        }
        private static let state = State()

        static func ensureLoaderDir(executableDir: URL) {
            state.ensureOnce {
                guard let dir = locateLoaderDirectory(executableDir: executableDir)
                else { return }

                KSLog.logger("platform.windows.webview").debug(
                    "WebView2Loader.dll directory resolved -> \(dir)")
                dir.withUTF16Pointer { ptr in
                    KSWV2_SetLoaderSearchDirectory(ptr)
                }
            }
        }

        /// 후보 디렉터리 중 `WebView2Loader.dll` 을 가진 첫 번째 경로를
        /// 반환한다. 테스트 가능하도록 순수 함수로 분리.
        static func locateLoaderDirectory(
            executableDir: URL,
            fileManager: FileManager = .default
        ) -> String? {
            for dir in candidateDirectories(
                executableDir: executableDir, fileManager: fileManager)
            {
                let dll = dir.appendingPathComponent("WebView2Loader.dll")
                if fileManager.fileExists(atPath: dll.path) {
                    return dir.path
                }
            }
            return nil
        }

        /// 우선순위 순으로 후보 디렉터리들을 반환한다.
        static func candidateDirectories(
            executableDir: URL,
            fileManager: FileManager = .default
        ) -> [URL] {
            var result: [URL] = [executableDir]

            let arch = currentArch()
            // EXE 부모를 거슬러 올라가며 `.build` 디렉터리를 찾는다.
            // 고정된 깊이(0..<5) 대신 `.build` 마커를 명시적으로 탐색하여 SwiftPM
            // 레이아웃이 변경되거나 출력 디렉터리가 깊어져도 동작하도록 한다.
            // 파일 시스템 루트에 도달하면 중단한다.
            var cursor: URL? = executableDir
            while let current = cursor {
                if current.lastPathComponent == ".build" {
                    let checkouts = current.appendingPathComponent("checkouts")
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(
                        atPath: checkouts.path, isDirectory: &isDir),
                        isDir.boolValue
                    {
                        if let entries = try? fileManager.contentsOfDirectory(
                            at: checkouts,
                            includingPropertiesForKeys: [.isDirectoryKey],
                            options: [.skipsHiddenFiles])
                        {
                            for entry in entries where entry.lastPathComponent.lowercased().contains("kalsae") {
                                let native =
                                    entry
                                    .appendingPathComponent("Sources")
                                    .appendingPathComponent("CKalsaeWV2")
                                    .appendingPathComponent("Vendor")
                                    .appendingPathComponent("WebView2")
                                    .appendingPathComponent("runtimes")
                                    .appendingPathComponent(arch)
                                    .appendingPathComponent("native")
                                result.append(native)
                            }
                        }
                    }
                    break
                }
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                cursor = parent
            }

            return result
        }

        private static func currentArch() -> String {
            #if arch(arm64)
                return "win-arm64"
            #else
                return "win-x64"
            #endif
        }
    }
#endif
