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

    /// 현재 디스패치 중인 명령의 등록 이름.
    ///
    /// `KSCommandRegistry.dispatch` 가 핸들러 호출 직전에 태스크 로컬로
    /// 설정한다. 핸들러 내부에서 자신의 명령 이름을 알아야 하는 로깅 /
    /// 메트릭 코드가 사용할 수 있다. 디스패치 외부 컨텍스트에서는 `nil`.
    @TaskLocal public static var commandName: String? = nil

    /// 현재 호출을 트리거한 페이지의 origin URL (스킴+호스트+선택적 포트).
    ///
    /// IPC 브리지가 명령을 디스패치하기 직전에 태스크 로컬로 설정한다.
    /// 로컬 가상 호스트(`ks://`, `file://`, `https://app.kalsae` …)에서의
    /// 호출은 빈 값이 아닌 실제 origin이 들어올 수 있다.
    /// 브리지가 origin을 알 수 없거나 직접 dispatch를 호출하는 컨텍스트에서는 `nil`.
    ///
    /// `KSCapability.remote.urls` 매칭과 정책 결정 캐시 키로 사용된다.
    @TaskLocal public static var origin: String? = nil
}
