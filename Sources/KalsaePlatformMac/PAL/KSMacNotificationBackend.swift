#if os(macOS)
internal import UserNotifications
public import KalsaeCore
public import Foundation

/// macOS implementation of `KSNotificationBackend` using UserNotifications.
public final class KSMacNotificationBackend: KSNotificationBackend, @unchecked Sendable {
    public init() {}

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    cont.resume(returning: granted)
                }
        }
    }

    public func post(_ notification: KSNotification) async throws(KSError) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = notification.title
        if let body = notification.body { content.body = body }

        // Map sound name to UNNotificationSound.
        if let sound = notification.sound, !sound.isEmpty {
            content.sound = sound.lowercased() == "default"
                ? .default
                : UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
        }

        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: nil)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            center.add(request) { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }
    }

    public func cancel(id: String) async {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
}
#endif