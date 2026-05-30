#if os(Android)
    public import KalsaeCore
    public import Foundation

    // MARK: - Android 권한 상태 (Android permission states)

    /// Android 기능에 대해 명시적인 권한 부여가 필요한 런타임 권한 상태를 나타냅니다.
    /// Swift 브리지가 시작되기 전에 Kotlin 호스트가 값을 채워넣습니다.
    ///
    /// Android 6.0 (API 23)부터 도입된 런타임 권한 모델에서는 앱이 실행 중에
    /// 사용자에게 권한을 요청하고, 사용자는 '허용', '거부', '영구 거부' 중
    /// 하나로 응답할 수 있습니다. 이 열거형은 그 세 가지 상태에 아직 요청하지
    /// 않은 초기 상태(`notDetermined`)를 추가하여 Kotlin ↔ Swift 간 권한 상태
    /// 동기화에 사용됩니다.
    public enum KSAndroidPermissionState: Sendable {
        /// 권한이 부여됨 — 해당 기능에 접근할 수 있습니다.
        case granted
        /// 권한이 거부됨 — 사용자에게 다시 요청할 수 있습니다.
        case denied
        /// 권한이 영구적으로 거부됨 — 시스템 설정 화면에서만 변경 가능합니다.
        /// 다시 요청해도 시스템 다이얼로그가 표시되지 않으며, 사용자를
        /// 설정 화면으로 안내해야 합니다.
        case permanentlyDenied
        /// 아직 권한이 요청되지 않은 초기 상태입니다.
        case notDetermined
    }

    // MARK: - 권한 저장소 (Permission registry)

    /// Android 런타임 권한 상태를 스레드 안전하게 저장하는 저장소입니다.
    /// Kotlin Activity가 Swift를 호출하기 전에 이 저장소의 값을 갱신합니다.
    ///
    /// 액터(actor) 대신 `NSLock`을 사용한 `@unchecked Sendable` 클래스인
    /// 이유: 정적 공유 인스턴스(`shared`)에 대한 동시 접근을 액터로 보호하면
    /// 동기(sync) 컨텍스트에서도 액터 경계를 넘어야 해서 오버헤드가 큽니다.
    /// `NSLock`은 단순한 임계 구역 보호에 적합하며, 권한 상태 조회/갱신은
    /// 매우 짧은 크리티컬 섹션이므로 병목이 발생하지 않습니다.
    // @unchecked: NSLock (정적 공유 인스턴스) — 액터는 정적 공유 가변 상태에 부적합
    public final class KSAndroidPermissions: @unchecked Sendable {
        private let lock = NSLock()
        private var _states: [String: KSAndroidPermissionState] = [:]

        /// 전역에서 접근 가능한 싱글톤 인스턴스입니다.
        public static let shared = KSAndroidPermissions()

        public init() {}

        /// `permission`(예: `"POST_NOTIFICATIONS"`)에 대한 현재 상태를 반환합니다.
        /// 아직 등록된 적 없는 권한은 `.notDetermined`로 간주합니다.
        /// - Parameter permission: Android 퍼미션 문자열 (예: `"android.permission.POST_NOTIFICATIONS"`)
        /// - Returns: 현재 권한 상태 (등록되지 않은 경우 `.notDetermined`)
        public func state(for permission: String) -> KSAndroidPermissionState {
            lock.withLock { _states[permission] ?? .notDetermined }
        }

        /// `permission`의 상태를 갱신합니다. Kotlin 호스트가 호출합니다.
        /// - Parameters:
        ///   - state: 설정할 새로운 권한 상태
        ///   - permission: 대상 Android 퍼미션 문자열
        public func setState(_ state: KSAndroidPermissionState, for permission: String) {
            lock.withLock { _states[permission] = state }
        }

        /// `permission`이 `.granted` 상태인지 여부를 반환합니다.
        /// - Parameter permission: 확인할 Android 퍼미션 문자열
        /// - Returns: 권한이 부여되었으면 `true`
        public func isGranted(_ permission: String) -> Bool {
            state(for: permission) == .granted
        }
    }

    // MARK: - 권한 인식 알림 백엔드 (Permission-aware notification backend)

    /// `KSAndroidNotificationBackend`를 확장하여 알림을 게시하기 전에
    /// Android `POST_NOTIFICATIONS` 권한(API 33+ 필요; 최소 지원 API는 26)을
    /// 확인하도록 업그레이드합니다.
    ///
    /// Android 13 (API 33)부터는 알림 게시에 `POST_NOTIFICATIONS` 런타임 권한이
    /// 필수입니다. 이 확장은 권한이 부여되지 않은 상태에서 알림을 보내려 하면
    /// 조기에 실패하여 사용자에게 명확한 오류 메시지를 전달합니다.
    extension KSAndroidNotificationBackend {
        /// `POST_NOTIFICATIONS` 권한이 부여된 경우에만 알림을 게시합니다.
        /// 권한이 거부되었거나 아직 결정되지 않은 경우 `.unsupportedPlatform`
        /// 오류를 던집니다. 호출자는 먼저 `requestPermission()`을 호출해야 합니다.
        /// - Parameters:
        ///   - notification: 게시할 알림 객체
        ///   - permissions: 권한 상태를 확인할 저장소 (기본값: `.shared`)
        /// - Throws: `KSError` — 권한이 없으면 `code: .unsupportedPlatform`
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

    // MARK: - 권한 인식 클립보드 백엔드 (Permission-aware clipboard backend)

    /// `KSAndroidClipboardBackend`를 확장하여 Android API 29부터 도입된
    /// 클립보드 접근 제한을 준수합니다.
    ///
    /// Android 10 (API 29)부터는 앱이 포그라운드에 있을 때만 클립보드 내용을
    /// 읽을 수 있습니다. 백그라운드에서 클립보드에 접근하면 빈 값이 반환되거나
    /// 예외가 발생합니다. 이 래퍼는 `isForeground` 플래그를 먼저 확인하여
    /// 포그라운드가 아닌 경우 명확한 오류 메시지와 함께 실패합니다.
    extension KSAndroidClipboardBackend {
        /// Android 클립보드 접근 제한(API 29+)을 준수하여 클립보드 텍스트를 읽습니다.
        /// 앱이 포그라운드에 있을 때만 `readText()`를 호출합니다.
        /// `isForeground` 값은 Kotlin 호스트에서 설정합니다.
        /// - Parameter isForeground: 현재 앱이 포그라운드에 있는지 여부
        /// - Returns: 클립보드 텍스트 (비어 있으면 `nil`)
        /// - Throws: `KSError` — 포그라운드가 아니면 `code: .unsupportedPlatform`
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

    // MARK: - 보안 정책 헬퍼 (Security policy helpers)

    /// Kalsae의 `KSSecurityConfig` 필드를 Android 기능 지원 여부에 매핑합니다.
    /// 부팅 시 `KSAndroidSecurityAdvisor.check(config:)`를 호출하여 Android에서
    /// 자동으로 무시(no-op)될 설정 항목을 로그로 기록합니다.
    ///
    /// Android는 데스크톱 OS(macOS/Windows/Linux)와 다른 플랫폼 특성을 가지므로,
    /// `kalsae.json`에 선언된 보안 설정 중 일부는 Android에서 적용되지 않을 수
    /// 있습니다. 이 어드바이저는 개발자가 설정 파일에 불필요하게 선언한 항목을
    /// 사전에 인지할 수 있도록 경고를 출력합니다.
    public struct KSAndroidSecurityAdvisor: Sendable {
        public init() {}

        /// 설정 파일에서 선언되었지만 Android에 대응하는 구현이 없는
        /// 보안 기능들을 로그로 경고합니다.
        /// - Parameter config: Kalsae 앱 설정 (`KSConfig`)
        public func check(config: KSConfig) {
            let log = KSLog.logger("platform.android.security")

            // 컨텍스트 메뉴(Context menu) 정책은 WebView 자체에서 JS 런타임을
            // 통해 제어되므로, Android에서 별도 플랫폼 재정의가 필요하지 않습니다.
            // WebView의 `onCreateContextMenu` 기본 동작을 JS가 preventDefault
            // 하는 방식으로 처리합니다.

            // 외부 드래그-드롭(External drop)은 Android WebView에서 기본적으로
            // 호스트가 파일 드롭을 브리지 이벤트로 가로채지 않으므로, 본 설정은
            // 사실상 암묵적으로 비활성화된 상태와 동일합니다.
            if !config.security.allowExternalDrop {
                log.info(
                    "security.allowExternalDrop=false is effectively implicit on Android "
                        + "(external file-drop bridge is not active by default)")
            }

            // Android credential backend는 Kotlin 호스트의 JNI 훅 등록이 있어야
            // 실제 저장소(예: AndroidKeyStore + EncryptedSharedPreferences)와
            // 연결된다. 훅이 없으면 credential API는 unsupportedPlatform을 반환한다.
            if config.security.secret.enabled {
                let bridge = KSAndroidJNIBridge.shared
                if bridge.credentialSet == nil
                    || bridge.credentialGet == nil
                    || bridge.credentialDelete == nil
                    || bridge.credentialList == nil
                {
                    log.warning(
                        "security.secret.enabled=true but Android credential JNI hooks are "
                            + "not fully registered; secret APIs may return unsupportedPlatform")
                }
            }

            // 시스템 트레이는 데스크톱 전용 UI 요소입니다.
            // Android에는 시스템 트레이 개념이 없으므로 트레이 관련 설정은
            // 모두 무시됩니다.
            if config.tray != nil {
                log.warning("config.tray is declared but Android has no system tray")
            }

            // 자동 시작(Autostart) 등록은 데스크톱 OS에서 일반적인 기능이지만,
            // Android는 시스템이 앱 수명 주기를 완전히 관리하므로 지원되지 않습니다.
            // Android에서 부팅 후 자동 실행이 필요한 경우, 부트 완료 리시버
            // (BOOT_COMPLETED BroadcastReceiver)를 Kotlin 측에서 직접 구현해야 합니다.
            if config.autostart != nil {
                log.warning("config.autostart is declared but Android does not support autostart registration")
            }
        }
    }
#endif
