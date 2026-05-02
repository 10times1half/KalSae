internal import Foundation

#if os(Windows)
    internal import KalsaePlatformWindows
#elseif os(macOS)
    internal import KalsaePlatformMac
#elseif os(Linux)
    internal import KalsaePlatformLinux
#endif
extension KSApp {

    /// 단일 인스턴스 획득 시도의 결과.
    public enum SingleInstanceOutcome: Sendable {
        /// 이 프로세스가 기본 인스턴스다. 정상 시작을 계속한다.
        case primary
        /// 다른 인스턴스가 이미 실행 중이며 인자가 전달되었다.
        /// 호출자는 즉시 종료해야 한다.
        case relayed
    }

    /// 한 번에 하나의 애플리케이션 인스턴스만 실행되도록 보장한다.
    ///
    /// 첫 번째 실행에서 이 프로세스가 **기본(primary)**이 되어
    /// `.primary`를 반환한다. 이후 실행은 기본 인스턴스를 감지하고
    /// 명령줄 인자를 전달한 후 `.relayed`를 반환한다 —
    /// 호출자는 즉시 종료해야 한다. 기본 인스턴스는 `onSecondInstance`
    /// (메인 스레드에서 호출됨)를 통해 전달된 인자를 수신한다.
    ///
    /// macOS에서는 `KSMacSingleInstance`에 위임한다.
    ///
    /// `boot(...)` **전에** 호출한다:
    /// ```swift
    /// switch await KSApp.singleInstance(identifier: "dev.example.MyApp") { args in
    ///     // 기존 윈도우에 포커스, `args` 파싱 등
    /// } {
    /// case .relayed: exit(EXIT_SUCCESS)
    /// case .primary: break
    /// }
    /// let app = try await KSApp.boot(configURL: configURL) { _ in }
    /// ```
    @MainActor
    public static func singleInstance(
        identifier: String,
        args: [String] = CommandLine.arguments,
        onSecondInstance: @escaping @MainActor ([String]) -> Void
    ) -> SingleInstanceOutcome {
        #if os(Windows)
            switch KSWindowsSingleInstance.acquire(
                identifier: identifier,
                args: args,
                onSecondInstance: onSecondInstance)
            {
            case .primary: return .primary
            case .relayed: return .relayed
            }
        #elseif os(macOS)
            switch KSMacSingleInstance.acquire(
                identifier: identifier,
                args: args,
                onSecondInstance: onSecondInstance)
            {
            case .primary: return .primary
            case .relayed: return .relayed
            }
        #elseif os(Linux)
            switch KSLinuxSingleInstance.acquire(
                identifier: identifier,
                args: args,
                onSecondInstance: onSecondInstance)
            {
            case .primary: return .primary
            case .relayed: return .relayed
            }
        #else
            _ = identifier
            _ = args
            _ = onSecondInstance
            return .primary
        #endif
    }
}
