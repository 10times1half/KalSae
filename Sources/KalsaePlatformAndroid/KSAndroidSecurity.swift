#if os(Android)
    public import KalsaeCore
    public import Foundation

    // MARK: - Android permission states

    /// Runtime permission states for Android features that require explicit grants.
    /// Populated by the Kotlin host before the Swift bridge starts.
    public enum KSAndroidPermissionState: Sendable {
        /// Permission has been granted.
        case granted
        /// Permission has been denied (user can still be prompted).
        case denied
        /// Permission was permanently denied (must go to Settings).
        case permanentlyDenied
        /// Permission has not been requested yet.
        case notDetermined
    }

    // MARK: - Permission registry

    /// Thread-safe store for Android runtime permission states.
    /// The Kotlin Activity updates these before calling into Swift.
    // @unchecked: NSLock (static shared instance) — actor unsuitable for static shared mutable state
    public final class KSAndroidPermissions: @unchecked Sendable {
        private let lock = NSLock()
        private var _states: [String: KSAndroidPermissionState] = [:]

        public static let shared = KSAndroidPermissions()

        public init() {}

        /// Returns the current state for `permission` (e.g. `"POST_NOTIFICATIONS"`).
        public func state(for permission: String) -> KSAndroidPermissionState {
            lock.withLock { _states[permission] ?? .notDetermined }
        }

        /// Updates the state for `permission`. Called by the Kotlin host.
        public func setState(_ state: KSAndroidPermissionState, for permission: String) {
            lock.withLock { _states[permission] = state }
        }

        /// Returns `true` when `permission` is `.granted`.
        public func isGranted(_ permission: String) -> Bool {
            state(for: permission) == .granted
        }
    }

    // MARK: - Permission-aware notification backend

    /// Upgrades `KSAndroidNotificationBackend` to check the Android
    /// `POST_NOTIFICATIONS` permission (required on API 33+; minimum supported API is 26) before posting.
    extension KSAndroidNotificationBackend {
        /// Posts a notification only when `POST_NOTIFICATIONS` is granted.
        /// Throws `.unsupportedPlatform` if the permission is denied or not yet
        /// determined — the caller should call `requestPermission()` first.
        public func postChecked(
            _ notification: KSNotification,
            permissions: KSAndroidPermissions = .shared
        ) async throws(KSError) {
            guard permissions.isGranted("POST_NOTIFICATIONS") else {
                throw KSError(
                    code: .unsupportedPlatform,
                    message: "POST_NOTIFICATIONS not granted — call requestPermission() first")
            }
            try await post(notification)
        }
    }

    // MARK: - Permission-aware clipboard backend

    extension KSAndroidClipboardBackend {
        /// Reads clipboard text, honouring the Android clipboard access
        /// restriction introduced in API 29 (apps can only read clipboard when
        /// they are in the foreground). This wrapper checks `isForeground` before
        /// calling `readText`; set it from the Kotlin host.
        public func readTextIfForeground(
            isForeground: Bool
        ) async throws(KSError) -> String? {
            guard isForeground else {
                throw KSError(
                    code: .unsupportedPlatform,
                    message: "Clipboard read blocked: app is not in the foreground (Android API 29+)")
            }
            return try await readText()
        }
    }

    // MARK: - Security policy helpers

    /// Maps Kalsae's `KSSecurityConfig` fields to Android capability checks.
    /// Call `KSAndroidSecurityAdvisor.check(config:)` at boot to log any
    /// configuration that will be silently no-op'd on Android.
    public struct KSAndroidSecurityAdvisor: Sendable {
        public init() {}

        /// Logs warnings for security features that are declared in the config
        /// but have no Android equivalent.
        public func check(config: KSConfig) {
            let log = KSLog.logger("platform.android.security")

            // Context menu policy is WebView-driven — always honoured via the JS
            // runtime; no platform override needed.

            // External drop is a desktop concept; no equivalent on Android.
            if !config.security.allowExternalDrop {
                log.info("security.allowExternalDrop=false is a no-op on Android (no drag-drop)")
            }

            // Tray commands will be missing on Android.
            if config.tray != nil {
                log.warning("config.tray is declared but Android has no system tray")
            }

            // Autostart is not applicable on Android.
            if config.autostart != nil {
                log.warning("config.autostart is declared but Android does not support autostart registration")
            }
        }
    }
#endif
