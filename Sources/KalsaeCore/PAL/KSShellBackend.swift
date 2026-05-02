/// 운영체제 셸 통합: 기본 브라우저에서 URL 열기, OS 파일 관리자에서
/// 파일 표시, 휴지통으로 이동 등.
///
/// 이 프로토콜의 메서드는 사용자 머신에 부작용을 수반하므로
/// 애플리케이션의 `security.shell` 허용 목록으로 게이팅해야 한다.
/// 모든 구현은 네이티브 UI 작업을 플랫폼 UI 스레드에서 실행해야 한다.
public import Foundation

/// 기본 no-op 구현: 모든 메서드는 `unsupportedPlatform`을 던진다.
/// 플랫폼은 개별 메서드를 재정의하여 기능을 추가한다.
public protocol KSShellBackend: Sendable {
    /// `url`을 시스템에 등록된 기본 핸들러로 연다.
    /// Wails의 `BrowserOpenURL`에 해당한다.
    func openExternal(_ url: URL) async throws(KSError)

    /// `url`(파일 또는 폴더)을 플랫폼 파일 관리자(Explorer / Finder / Files)에서
    /// 표시하고 가능한 경우 항목을 선택한다.
    func showItemInFolder(_ url: URL) async throws(KSError)

    /// `url`을 플랫폼의 휴지통으로 이동한다. 파일 시스템 항목은 영구
    /// 삭제되지 않는다.
    func moveToTrash(_ url: URL) async throws(KSError)
}
extension KSShellBackend {
    @inline(__always)
    private func _unsupportedThrow(_ op: String) throws(KSError) -> Never {
        throw KSError(
            code: .unsupportedPlatform,
            message: "KSShellBackend.\(op) is not implemented on this platform.")
    }

    public func openExternal(_ url: URL) async throws(KSError) { try _unsupportedThrow("openExternal") }
    public func showItemInFolder(_ url: URL) async throws(KSError) { try _unsupportedThrow("showItemInFolder") }
    public func moveToTrash(_ url: URL) async throws(KSError) { try _unsupportedThrow("moveToTrash") }
}
