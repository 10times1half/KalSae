/// 라이브 윈도우의 뺈타입 식별자. 플랫폼 레이어는 네이티브 객체로
/// 해석할 수 있는 구체적인 핸들을 제공한다(NSWindow, HWND, GtkWindow).
import Foundation

/// 최상위 플랫폼 추상화. 각 OS는 정확히 하나의 철혷 타입을 제공한다
/// (예: `KSMacPlatform`, `KSWindowsPlatform`, `KSLinuxPlatform`).
///
/// 엄브레라 모듈은 `#if os(...)`를 통해 컴파일 시점에 올바른 것을 선택한다.

// MARK: - Source-compatible defaults

public struct KSWindowHandle: Hashable, Sendable {
    public let label: String
    public let rawValue: UInt64
    public init(label: String, rawValue: UInt64) {
        self.label = label
        self.rawValue = rawValue
    }
}
public protocol KSPlatform: Sendable {
    /// 이 백엔드의 사람이 읽을 수 있는 이름(로그용).
    var name: String { get }

    /// 이 플랫폼의 윈도우 백엔드.
    var windows: any KSWindowBackend { get }

    /// 다이얼로그 백엔드(파일/저장/폴더/메시지).
    var dialogs: any KSDialogBackend { get }

    /// 트레이(상태 표시줄 아이템) 백엔드. 일부 환경(Wayland 컴포지터 등)에서는
    /// 지원되지 않으므로 선택적이다.
    var tray: (any KSTrayBackend)? { get }

    /// 네이티브 메뉴 백엔드.
    var menus: any KSMenuBackend { get }

    /// 알림 백엔드.
    var notifications: any KSNotificationBackend { get }

    /// 운영체제 셸 통합(외부 URL 열기, 파일 관리자에서 표시, 휴지통으로 이동 등).
    /// 셔러 백엔드를 아직 구현하지 않은 플랫폼은 `nil`을 반환한다.
    var shell: (any KSShellBackend)? { get }

    /// 시스템 클립보드. `shell`과 동일한 이유로 선택적이다.
    var clipboard: (any KSClipboardBackend)? { get }

    /// 전역 키보드 가속기(핫키) 백엔드. 일부 플랫폼(샌드박스 등)에서는
    /// 전역 핫키를 지원하지 않으므로 선택적이다.
    var accelerators: (any KSAcceleratorBackend)? { get }

    /// 자동 시작 백엔드. 로그인 시 실행을 지원하지 않는 플랫폼(iOS 샌드박스,
    /// Android)에서는 `nil`이다.
    var autostart: (any KSAutostartBackend)? { get }

    /// 딥 링크(커스텀 URL 스킴) 백엔드. 딥 링크 등록을 아직 구현하지 않은
    /// 플랫폼에서는 `nil`이다.
    var deepLink: (any KSDeepLinkBackend)? { get }

    /// 네이티브 애플리케이션을 부트스트랩하고(NSApplication / Win32 메시지 루프 /
    /// GApplication) 종료될 때까지 실행한다.
    ///
    /// - Parameter configure: 플랫폼이 초기화된 후, 런 루프가 시작되기 전에 호출된다.
    func run(
        config: KSConfig,
        configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
    ) async throws(KSError) -> Never
}
extension KSPlatform {
    /// 기본값: 플랫폼이 솔 백엔드를 아직 노출하지 않는다.
    public var shell: (any KSShellBackend)? { nil }

    /// 기본값: 플랫폼이 클립보드 백엔드를 아직 노출하지 않는다.
    public var clipboard: (any KSClipboardBackend)? { nil }

    /// 기본값: 플랫폼이 전역 가속기 백엔드를 아직 노출하지 않는다.
    public var accelerators: (any KSAcceleratorBackend)? { nil }

    /// 기본값: 플랫폼이 자동 시작 백엔드를 노옶하지 않는다.
    public var autostart: (any KSAutostartBackend)? { nil }

    /// 기본값: 플랫폼이 딥 링크 백엔드를 노옶하지 않는다.
    public var deepLink: (any KSDeepLinkBackend)? { nil }
}
