import Foundation

/// Desktop notifications.
public protocol KSNotificationBackend: Sendable {
    /// Requests user permission where required (macOS). Returns `true` when
    /// notifications are permitted after the call.
    func requestPermission() async -> Bool

    /// Posts a notification. `id` may be used to replace/cancel later.
    func post(_ notification: KSNotification) async throws(KSError)

    func cancel(id: String) async
}

public struct KSNotification: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var body: String?
    public var iconPath: String?
    /// Sound name or `nil` for silent. Platform layer maps to native sounds.
    public var sound: String?

    public init(id: String,
                title: String,
                body: String? = nil,
                iconPath: String? = nil,
                sound: String? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.iconPath = iconPath
        self.sound = sound
    }
}
