/// 전역 키보드 가속기(핫키) 등록.
///
/// Windows에서는 `RegisterHotKey` / `WM_HOTKEY`에 매핑된다(앱이
/// 포커스를 잃어도 발동하는 시스템 전역 단축키).
/// macOS / Linux 구현은 이후 단계에서 추가된다.
///
/// 가속기 문자열은 `KSMenuItem.accelerator`와 동일한 크로스플랫폼 표기를 사용한다:
/// - `"CmdOrCtrl+Shift+N"` → Windows/Linux에서 `Ctrl+Shift+N`
/// - `"Alt+F4"`, `"Ctrl+Space"`, `"F11"`, `"Ctrl+Plus"`
public protocol KSAcceleratorBackend: Sendable {
    /// `accelerator`를 등록하고 `handler`에 바인딩한다. 동일한 `id`로
    /// 재등록할 수 있다(기존 바인딩이 먼저 교체된다).
    /// - Throws: 파싱 불가능한 가속기는 `.invalidArgument`, OS가 등록을
    ///   거부하면(예: 다른 프로세스가 이미 해당 핫키 소유) `.platformInitFailed`.
    func register(id: String,
                  accelerator: String,
                  _ handler: @Sendable @escaping () -> Void) async throws(KSError)

    /// `id`에 대해 설치된 바인딩을 등록 해제한다. `id`가 없으면 no-op.
    func unregister(id: String) async throws(KSError)

    /// 이 백엔드가 소유한 모든 등록을 제거한다.
    func unregisterAll() async throws(KSError)
}

extension KSAcceleratorBackend {
    @inline(__always)
    private func _unsupported(_ op: String) throws(KSError) -> Never {
        throw KSError(code: .unsupportedPlatform,
                      message: "KSAcceleratorBackend.\(op) is not implemented on this platform.")
    }

    public func register(id: String,
                         accelerator: String,
                         _ handler: @Sendable @escaping () -> Void) async throws(KSError) {
        try _unsupported("register")
    }

    public func unregister(id: String) async throws(KSError) {
        try _unsupported("unregister")
    }

    public func unregisterAll() async throws(KSError) {
        try _unsupported("unregisterAll")
    }
}
