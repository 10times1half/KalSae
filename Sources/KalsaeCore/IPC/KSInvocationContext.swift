/// 현재 IPC 호출의 컨텍스트 정보.
///
/// 명령 핸들러(`@KSCommand`)는 이 타입으로 어느 창에서 호출이 왔는지
/// 확인할 수 있다.
///
/// ```swift
/// @KSCommand func greet(_ name: String) -> String {
///     let window = KSInvocationContext.windowLabel ?? "unknown"
///     return "Hello from \(window)!"
/// }
/// ```
public enum KSInvocationContext {
    /// 현재 호출을 트리거한 창의 레이블.
    ///
    /// IPC 브리지가 명령을 디스패치할 때 태스크 로컬로 설정된다.
    /// 브리지가 없는 컨텍스트(예: 직접 `registry.dispatch` 호출)에서는
    /// `nil`이다.
    @TaskLocal public static var windowLabel: String? = nil
}
