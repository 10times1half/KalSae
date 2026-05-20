#if os(iOS)
    internal import UserNotifications
    public import KalsaeCore
    public import Foundation

    /// iOS 로컬 알림(Local Notification)을 관리하는 `KSNotificationBackend` 구현체입니다.
    ///
    /// Apple의 `UserNotifications` 프레임워크를 사용하여 로컬 알림을
    /// 스케줄링하고 게시합니다. iOS 10 이상에서 사용 가능하며, 알림 권한
    /// 요청(`requestPermission`)이 선행되어야 알림을 게시할 수 있습니다.
    ///
    /// - 알림 권한: `.alert`, `.sound`, `.badge` 옵션을 요청합니다.
    /// - 알림 트리거: `post()`는 즉시 표시되는 트리거 없는 알림을 생성합니다.
    /// - 알림 취소: 이미 전달된 알림과 대기 중인 알림을 모두 제거합니다.
    ///
    /// - Note: `@unchecked Sendable` — `UNUserNotificationCenter`의 모든
    ///   메서드는 스레드 안전하므로 추가 동기화가 필요하지 않습니다.
    public final class KSiOSNotificationBackend: KSNotificationBackend, @unchecked Sendable {
        public init() {}

        /// 사용자에게 알림 권한을 요청합니다.
        /// iOS에서는 시스템 알림 허용 다이얼로그가 표시됩니다.
        /// - Returns: 사용자가 권한을 허용하면 `true`, 거부하면 `false`
        public func requestPermission() async -> Bool {
            await withCheckedContinuation { cont in
                UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        cont.resume(returning: granted)
                    }
            }
        }

        /// 로컬 알림을 즉시 게시합니다.
        /// `requestPermission()`이 선행되어야 하며, 권한이 없으면 알림이
        /// 표시되지 않습니다.
        /// - Parameter notification: 게시할 알림 정보 (제목, 본문, 사운드)
        /// - Throws: `KSError` — UserNotifications 프레임워크 오류 시
        public func post(_ notification: KSNotification) async throws(KSError) {
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = notification.title
            if let body = notification.body { content.body = body }

            if let sound = notification.sound, !sound.isEmpty {
                content.sound =
                    sound.lowercased() == "default"
                    ? .default
                    : UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
            }

            let request = UNNotificationRequest(
                identifier: notification.id,
                content: content,
                trigger: nil)

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                center.add(request) { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        }

        /// 특정 알림 ID를 취소(제거)합니다.
        /// 이미 전달된 알림과 아직 전달되지 않은 대기 중인 알림을 모두 제거합니다.
        /// - Parameter id: 취소할 알림의 고유 식별자
        public func cancel(id: String) async {
            let center = UNUserNotificationCenter.current()
            center.removeDeliveredNotifications(withIdentifiers: [id])
            center.removePendingNotificationRequests(withIdentifiers: [id])
        }
    }
#endif
