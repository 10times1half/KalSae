/// Kalsae의 중앙 로깅 파사드.
///
/// 플랫폼 백엔드는 ``bootstrap(factory:)``를 통해 네이티브 `LogHandler`를
/// 등록한다(예: macOS에서 `os.Logger`, Windows에서 `OutputDebugStringW`).
/// `bootstrap` 호출 전에는 `swift-log`의 기본 stderr 핸들러가 사용된다.
import Foundation
public import Logging

public enum KSLog {
    /// 플랫폼 로그 싱크가 사용하는 서브시스템 / 리버스 DNS 레이블.
    public static let subsystem = "dev.Kalsae"

    /// 애플리케이션 시작 초기에 한 번 호출한다. 여러 번 호출해도 안전하지만
    /// 첫 번째 호출만 효과가 있다(`swift-log` 계약).
    public static func bootstrap(
        _ factory: @Sendable @escaping (String) -> any LogHandler
    ) {
        LoggingSystem.bootstrap(factory)
    }

    /// 주어진 카테고리에 대한 편의 로거.
    public static func logger(_ category: String) -> Logger {
        Logger(label: "\(subsystem).\(category)")
    }
}
