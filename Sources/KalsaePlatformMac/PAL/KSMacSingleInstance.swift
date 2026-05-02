#if os(macOS)
    internal import AppKit
    public import KalsaeCore
    public import Foundation

    /// Single-instance helper for macOS applications.
    ///
    /// Uses `NSRunningApplication` to detect existing instances and
    /// `NSWorkspace.open` to forward arguments.
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
                // Forward args to the existing instance via AppleEvent.
                if let app = others.first, let appURL = app.bundleURL ?? app.executableURL {
                    let config = NSWorkspace.OpenConfiguration()
                    config.arguments = Array(args.dropFirst())
                    NSWorkspace.shared.openApplication(
                        at: appURL,
                        configuration: config
                    ) { _, _ in }
                }
                return .relayed
            }

            // Install listener for subsequent launches.
            KSMacDeepLinkBackend.installAppleEventHandler()
            return .primary
        }
    }
#endif
