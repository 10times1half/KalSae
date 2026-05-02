/// 선택적 자동 시작 설정. Tauri의 `plugin-autostart`를 따른다.
///
/// 이 섹션이 존재하면 `__ks.autostart.*` JS 명령은
/// `app.identifier`에서 파생된 이름의 OS 수준 "로그인 시 실행"
/// 등록 항목을 대상으로 동작한다.
///
/// Windows에서는
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\<identifier>`를
/// 읽고 쓴다. macOS/Linux는 추후 구현된다. 그 전까지도 설정은 파싱되며,
/// JS는 명령을 호출할 수 있지만 `isEnabled`는 `false`를 반환하고
/// `enable`/`disable`은 `unsupportedPlatform`을 던진다.
import Foundation

/// 선택적 딥링크 설정. Tauri의 `plugin-deep-link`를 따른다.
///
/// 여기에 나열된 스킴은 OS에 등록되어 브라우저나 다른 앱에서 호출된
/// `<scheme>://...` URL이 이 앱으로 전달될 수 있다. 이런 URL로 두 번째
/// 인스턴스가 실행되면 `KSApp.singleInstance`가 URL을 기본 인스턴스로 전달하고,
/// `__ks.deepLink.openURL`이 JS 이벤트로 방출된다.
public struct KSAutostartConfig: Codable, Sendable, Equatable {
    /// 등록된 EXE 호출 뒤에 붙는 추가 명령줄 인자.
    /// 자동 시작된 프로세스가 사용자 실행이 아닌 OS 실행임을 구분하는 데 유용하다.
    public var args: [String]

    public init(args: [String] = []) {
        self.args = args
    }

    private enum CodingKeys: String, CodingKey { case args }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
    }
}
public struct KSDeepLinkConfig: Codable, Sendable, Equatable {
    /// 점유할 URL 스킴 목록. 예: `["myapp", "myapp-dev"]`.
    /// 스킴은 소문자로 정규화되며, RFC 3986상 스킴에는 `:`와 `/`가 허용되지 않으므로
    /// Kalsae는 그런 문자를 포함한 스킴을 등록 시 거부한다.
    public var schemes: [String]
    /// `true`이면 `KSApp.boot`가 첫 실행 시 모든 스킴을 OS에 등록한다(멱등).
    /// `false`이면 JS의 `__ks.deepLink.register` 또는 호스트 설치 프로그램이
    /// 명시적으로 등록해야 한다.
    public var autoRegisterOnLaunch: Bool

    public init(schemes: [String] = [], autoRegisterOnLaunch: Bool = false) {
        self.schemes = schemes
        self.autoRegisterOnLaunch = autoRegisterOnLaunch
    }

    private enum CodingKeys: String, CodingKey {
        case schemes, autoRegisterOnLaunch
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemes = try c.decodeIfPresent([String].self, forKey: .schemes) ?? []
        self.autoRegisterOnLaunch =
            try c.decodeIfPresent(
                Bool.self, forKey: .autoRegisterOnLaunch) ?? false
    }
}
