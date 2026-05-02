/// 자동 시작("로그인 시 실행") 기능에 대한 PAL 계약.
///
/// 이 기능을 구현하는 플랫폼은 세 가지 작업을 제공한다: enable,
/// disable, isEnabled. 세 작업 모두 호출 액터에서 실행될 수 있으며
/// 구현은 저렴해야 한다(레지스트리 또는 plist 편집).
///
/// - Windows: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\<identifier>`에 기록.
/// - macOS  : 예약됨 (`SMAppService`를 통한 Login Items — 아직 미출시).
/// - Linux  : 예약됨 (XDG autostart `.desktop` 파일 — 아직 미출시).
public protocol KSAutostartBackend: Sendable {
    func enable() throws(KSError)
    func disable() throws(KSError)
    func isEnabled() -> Bool
}
