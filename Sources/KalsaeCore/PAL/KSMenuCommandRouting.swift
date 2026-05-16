import Foundation

/// 메뉴 / 트레이 클릭 이벤트를 구독자로 라우팅하는 플랫폼 공통 추상화.
///
/// 각 플랫폼의 메뉴 백엔드(`KSWindowsCommandRouter`, `KSMacCommandRouter`,
/// `KSLinuxCommandRouter`, `KSiOSCommandRouter`, `KSAndroidCommandRouter`)는
/// 이 프로토콜을 채택해 동일한 형태의 sink를 노출한다. `KSApp`는 이를 통해
/// OS 분기 없이 (a) `"menu"` 이벤트 방출과 (b) `@KSCommand` 레지스트리
/// 디스패치를 단일 위치에서 연결한다.
@MainActor
public protocol KSMenuCommandRouting: AnyObject {
    typealias Sink = @MainActor (_ command: String, _ itemID: String?) -> Void

    /// 명령 구독자를 추가한다. `KSMenuItem.command`가 `nil`이 아닌 모든
    /// 메뉴 / 트레이 클릭마다 호출된다.
    func subscribe(_ sink: @escaping Sink)

    /// 등록된 모든 구독자를 제거한다.
    func clear()
}
