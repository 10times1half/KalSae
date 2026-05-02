/// 데스크탑 알림.
import Foundation

public protocol KSNotificationBackend: Sendable {
    /// 필요한 경우(macOS) 사용자 권한을 요청한다. 알림이 허용되면 `true`를
    /// 반환한다.
    func requestPermission() async -> Bool

    /// 알림을 게시한다. `id`는 이후 교체/취소에 사용될 수 있다.
    func post(_ notification: KSNotification) async throws(KSError)

    func cancel(id: String) async
}
public struct KSNotification: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var body: String?
    public var iconPath: String?
    /// 소리 이름 또는 무음을 위해 `nil`. 플랫폼 레이어가 네이티브 소리에 매핑한다.
    public var sound: String?

    public init(
        id: String,
        title: String,
        body: String? = nil,
        iconPath: String? = nil,
        sound: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.iconPath = iconPath
        self.sound = sound
    }
}
