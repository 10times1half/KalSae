#if os(macOS)
    internal import AppKit
    public import KalsaeCore
    public import Foundation

    /// Single-instance helper for macOS applications.
    ///
    /// Uses `NSRunningApplication` to detect existing instances. For URL-form
    /// arguments (deep links), forwards them via `NSWorkspace.shared.open(_:)`
    /// which delivers `kAEGetURL` Apple Events to the running instance — the
    /// already-installed `installAppleEventHandler()` picks them up and routes
    /// through `KSMacAppleEventRouter`.
    ///
    /// **Limitation (RFC-004 §7):** `NSWorkspace.OpenConfiguration.arguments`
    /// per Apple's docs is only honoured when launching a *new* instance. When
    /// the target app is already running, those arguments are dropped — macOS
    /// only sends `kAEReopenApplication` without payload. Plain (non-URL) CLI
    /// arguments are therefore **not relayed** today; the `onSecondInstance`
    /// callback is invoked with the local args only when a second instance
    /// detects an already-running primary. A proper IPC channel
    /// (Distributed Notifications / XPC) is tracked as future work.
    public enum KSMacSingleInstance {

        public enum Outcome: Sendable {
            case primary
            case relayed
        }

        @MainActor
        public static func acquire(
            identifier: String,
            args: [String] = CommandLine.arguments,
            onSecondInstance: @escaping @MainActor ([String]) -> Void
        ) -> Outcome {
            let bundleID = Bundle.main.bundleIdentifier ?? identifier
            let runningApps = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleID)

            // 현재 프로세스를 제외한 인스턴스가 있으면 relay.
            let others = runningApps.filter {
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }

            if !others.isEmpty {
                if let app = others.first, let appURL = app.bundleURL ?? app.executableURL {
                    let payload = Array(args.dropFirst())
                    // URL 인자는 `NSWorkspace.shared.open([URL])`을 통해 `kAEGetURL`
                    // Apple Event로 정확히 전달된다 — 실행 중인 인스턴스의
                    // `installAppleEventHandler()`이 이를 받아 라우팅한다.
                    let urls: [URL] = payload.compactMap { arg in
                        guard arg.contains(":"),
                            let url = URL(string: arg),
                            url.scheme != nil
                        else { return nil }
                        return url
                    }
                    if !urls.isEmpty {
                        let config = NSWorkspace.OpenConfiguration()
                        NSWorkspace.shared.open(
                            urls, withApplicationAt: appURL,
                            configuration: config
                        ) { _, _ in }
                    } else {
                        // 비-URL CLI 인자는 OpenConfiguration.arguments로
                        // 새 인스턴스에만 전달되며 이미 실행 중인 인스턴스에는
                        // 도달하지 않는다 (Apple 문서). 단순 reopen만 발생.
                        let config = NSWorkspace.OpenConfiguration()
                        config.arguments = payload
                        NSWorkspace.shared.openApplication(
                            at: appURL,
                            configuration: config
                        ) { _, _ in }
                    }
                }
                return .relayed
            }

            // Install listener for subsequent launches.
            KSMacDeepLinkBackend.installAppleEventHandler()
            return .primary
        }
    }
#endif
