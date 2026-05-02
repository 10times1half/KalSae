/// 딥 링크 / 커스텀 URL 스킴 기능에 대한 PAL 계약.
///
/// 구현체는 `<scheme>://` URL을 OS에 등록하여 브라우저나 다른 앱에서
/// 해당 URL을 호출하면 이 앱이 실행(또는 재사용)되도록 한다.
/// `KSApp.singleInstance`와 함께 URL이 기본 인스턴스로 전달되고
/// JS에 `__ks.deepLink.openURL` 이벤트로 노출된다.
///
/// - Windows: `HKCU\Software\Classes\<scheme>` 기록(사용자 수준, 관리자 권한 불필요).
///   기본 ProgID는 `<identifier>.<scheme>`이다.
/// - macOS  : 예약됨 (`Info.plist`의 `CFBundleURLTypes`에 선언 — 번들 빌드 시 처리).
/// - Linux  : 예약됨 (XDG `.desktop` MimeType 연관).
public protocol KSDeepLinkBackend: Sendable {
    /// `scheme`을 OS에 등록하여 `<scheme>://...` 외부 호출이 이 실행 파일로
    /// 라우팅되도록 한다. 멱등 연산.
    func register(scheme: String) throws(KSError)

    /// `scheme`의 레지스트리 항목을 제거한다. 멱등 연산 — 항목이 없으면
    /// 성공으로 처리된다.
    func unregister(scheme: String) throws(KSError)

    /// `scheme`이 현재 이 실행 파일을 가리키도록 등록되어 있으면 `true`를
    /// 반환한다(`shell\open\command` 값의 문자열 일치).
    func isRegistered(scheme: String) -> Bool

    /// 현재 프로세스의 커맨드라인에서 `schemes`에 포함된 스킴을 가진 URL을
    /// 모두 반환한다. 시작 시 두 번째 인스턴스에서 릴레이된 URL과 동일하게
    /// 페이지에 노출하는 데 사용된다.
    func currentLaunchURLs(forSchemes schemes: [String]) -> [String]

    /// 두 번째 인스턴스에서 릴레이된 인자를 필터링하여 `schemes`에 포함된
    /// 스킴을 가진 딥 링크 URL만 반환한다.
    func extractURLs(fromArgs args: [String], forSchemes schemes: [String]) -> [String]
}
