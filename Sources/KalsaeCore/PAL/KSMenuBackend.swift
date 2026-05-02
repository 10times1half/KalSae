/// `KSMenuConfig`에 기술된 애플리케이션/윈도우/컨텍스트 메뉴를 설치한다.
import Foundation

public protocol KSMenuBackend: Sendable {
    func installAppMenu(_ items: [KSMenuItem]) async throws(KSError)
    func installWindowMenu(
        _ handle: KSWindowHandle,
        items: [KSMenuItem]) async throws(KSError)

    /// 화면 절대 좌표의 지정된 위치에 컨텍스트 메뉴를 표시한다.
    func showContextMenu(
        _ items: [KSMenuItem],
        at point: KSPoint,
        in handle: KSWindowHandle?) async throws(KSError)
}
public struct KSPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
