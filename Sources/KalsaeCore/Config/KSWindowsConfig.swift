/// Windows 전용 번들 설정. Tauri `bundle.windows` 스키마를 1:1 미러링한다.
///
/// `kalsae.json`의 `windows` 노드로 직렬화된다. CLI 플래그(`--msi*`,
/// `--windows-*`)는 여기 정의된 값을 오버라이드한다.
///
/// 모든 필드는 선택사항이며, MSI/NSIS 패키저는 누락된 값을 안전한 기본값으로
/// 처리한다.
import Foundation

// MARK: - 루트

public struct KSWindowsConfig: Codable, Sendable, Equatable {
    /// 다운그레이드 설치 허용 여부. Tauri 기본은 `true`.
    /// `false`면 WiX는 `MajorUpgrade DowngradeErrorMessage`를 강제한다.
    public var allowDowngrades: Bool
    /// MSI 시작 시 요구되는 WebView2 Runtime 최소 버전.
    /// 미달 시 `webviewInstallMode`가 트리거된다.
    public var minimumWebview2Version: String?
    /// 코드사이닝 명령. `.string`은 `signtool.exe sign /a %1` 형식,
    /// `.command`는 `{cmd, args}` 분리 형식. `%1`/`{file}` 플레이스홀더가
    /// 대상 파일 절대 경로로 치환된다.
    public var signCommand: KSSignCommand?
    /// 레거시 signtool 필드 (Tauri 호환). 지정 시 `signCommand`로 자동 합성.
    public var certificateThumbprint: String?
    public var digestAlgorithm: String?
    public var timestampUrl: String?
    /// RFC 3161 timestamping 사용 여부. 기본 `true`.
    public var tsp: Bool
    /// WebView2 Runtime 설치 모드.
    public var webviewInstallMode: KSWebView2InstallMode
    /// WiX (MSI) 전용 옵션.
    public var wix: KSWiXConfigDecl?

    public init(
        allowDowngrades: Bool = true,
        minimumWebview2Version: String? = nil,
        signCommand: KSSignCommand? = nil,
        certificateThumbprint: String? = nil,
        digestAlgorithm: String? = nil,
        timestampUrl: String? = nil,
        tsp: Bool = true,
        webviewInstallMode: KSWebView2InstallMode = .downloadBootstrapper(silent: true),
        wix: KSWiXConfigDecl? = nil
    ) {
        self.allowDowngrades = allowDowngrades
        self.minimumWebview2Version = minimumWebview2Version
        self.signCommand = signCommand
        self.certificateThumbprint = certificateThumbprint
        self.digestAlgorithm = digestAlgorithm
        self.timestampUrl = timestampUrl
        self.tsp = tsp
        self.webviewInstallMode = webviewInstallMode
        self.wix = wix
    }

    private enum CodingKeys: String, CodingKey {
        case allowDowngrades, minimumWebview2Version, signCommand
        case certificateThumbprint, digestAlgorithm, timestampUrl, tsp
        case webviewInstallMode, wix
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.allowDowngrades =
            try c.decodeIfPresent(Bool.self, forKey: .allowDowngrades) ?? true
        self.minimumWebview2Version =
            try c.decodeIfPresent(String.self, forKey: .minimumWebview2Version)
        self.signCommand = try c.decodeIfPresent(KSSignCommand.self, forKey: .signCommand)
        self.certificateThumbprint =
            try c.decodeIfPresent(String.self, forKey: .certificateThumbprint)
        self.digestAlgorithm = try c.decodeIfPresent(String.self, forKey: .digestAlgorithm)
        self.timestampUrl = try c.decodeIfPresent(String.self, forKey: .timestampUrl)
        self.tsp = try c.decodeIfPresent(Bool.self, forKey: .tsp) ?? true
        self.webviewInstallMode =
            try c.decodeIfPresent(KSWebView2InstallMode.self, forKey: .webviewInstallMode)
            ?? .downloadBootstrapper(silent: true)
        self.wix = try c.decodeIfPresent(KSWiXConfigDecl.self, forKey: .wix)
    }
}

// MARK: - WiX 옵션 (Tauri WixConfig 미러)

public struct KSWiXConfigDecl: Codable, Sendable, Equatable {
    /// 자동 생성된 UpgradeCode (`<productName>.exe.app.<arch>` DNS namespace v5)를
    /// 덮어쓰는 명시적 UUID. **한 번 릴리스되면 절대 바뀌면 안 된다** —
    /// 동일 UpgradeCode를 유지해야 업그레이드/제거가 호환된다.
    public var upgradeCode: String?
    /// MSI `ProductVersion` 오버라이드 (`M.m.p[.b]`, 0–65535). 미설정 시
    /// `app.version`을 정규화해 사용.
    public var version: String?
    /// MSI 언어 목록. 단일 문자열, 배열, 또는 `{ langTag: { localePath } }` 맵.
    public var language: KSWiXLanguage
    /// 사용자 제공 `.wxs` 메인 템플릿 경로 (kalsae 기본 템플릿 대체).
    public var template: String?
    /// 추가로 컴파일에 포함할 `.wxs` 조각 경로.
    public var fragmentPaths: [String]
    /// 메인 Feature에 끼워 넣을 `<ComponentRef Id="..."/>` 목록.
    public var componentRefs: [String]
    /// 메인 Feature에 끼워 넣을 `<ComponentGroupRef Id="..."/>` 목록.
    public var componentGroupRefs: [String]
    /// 메인 Feature에 끼워 넣을 `<FeatureRef Id="..."/>` 목록.
    public var featureRefs: [String]
    /// `<FeatureGroupRef Id="..."/>` 목록.
    public var featureGroupRefs: [String]
    /// `<MergeRef Id="..."/>` 목록.
    public var mergeRefs: [String]
    /// 인스톨러 상단 배너 BMP (493×58).
    public var bannerPath: String?
    /// 인스톨러 다이얼로그 배경 BMP (493×312).
    public var dialogImagePath: String?
    /// `true`면 자동 업데이트 작업을 elevated 권한으로 등록한다.
    public var enableElevatedUpdateTask: Bool
    /// `true`면 FIPS-compliant 해시 알고리즘만 사용한다.
    public var fipsCompliant: Bool

    public init(
        upgradeCode: String? = nil,
        version: String? = nil,
        language: KSWiXLanguage = .single("en-US"),
        template: String? = nil,
        fragmentPaths: [String] = [],
        componentRefs: [String] = [],
        componentGroupRefs: [String] = [],
        featureRefs: [String] = [],
        featureGroupRefs: [String] = [],
        mergeRefs: [String] = [],
        bannerPath: String? = nil,
        dialogImagePath: String? = nil,
        enableElevatedUpdateTask: Bool = false,
        fipsCompliant: Bool = false
    ) {
        self.upgradeCode = upgradeCode
        self.version = version
        self.language = language
        self.template = template
        self.fragmentPaths = fragmentPaths
        self.componentRefs = componentRefs
        self.componentGroupRefs = componentGroupRefs
        self.featureRefs = featureRefs
        self.featureGroupRefs = featureGroupRefs
        self.mergeRefs = mergeRefs
        self.bannerPath = bannerPath
        self.dialogImagePath = dialogImagePath
        self.enableElevatedUpdateTask = enableElevatedUpdateTask
        self.fipsCompliant = fipsCompliant
    }

    private enum CodingKeys: String, CodingKey {
        case upgradeCode, version, language, template, fragmentPaths
        case componentRefs, componentGroupRefs, featureRefs, featureGroupRefs, mergeRefs
        case bannerPath, dialogImagePath, enableElevatedUpdateTask, fipsCompliant
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.upgradeCode = try c.decodeIfPresent(String.self, forKey: .upgradeCode)
        self.version = try c.decodeIfPresent(String.self, forKey: .version)
        self.language = try c.decodeIfPresent(KSWiXLanguage.self, forKey: .language) ?? .single("en-US")
        self.template = try c.decodeIfPresent(String.self, forKey: .template)
        self.fragmentPaths = try c.decodeIfPresent([String].self, forKey: .fragmentPaths) ?? []
        self.componentRefs = try c.decodeIfPresent([String].self, forKey: .componentRefs) ?? []
        self.componentGroupRefs =
            try c.decodeIfPresent([String].self, forKey: .componentGroupRefs) ?? []
        self.featureRefs = try c.decodeIfPresent([String].self, forKey: .featureRefs) ?? []
        self.featureGroupRefs =
            try c.decodeIfPresent([String].self, forKey: .featureGroupRefs) ?? []
        self.mergeRefs = try c.decodeIfPresent([String].self, forKey: .mergeRefs) ?? []
        self.bannerPath = try c.decodeIfPresent(String.self, forKey: .bannerPath)
        self.dialogImagePath = try c.decodeIfPresent(String.self, forKey: .dialogImagePath)
        self.enableElevatedUpdateTask =
            try c.decodeIfPresent(Bool.self, forKey: .enableElevatedUpdateTask) ?? false
        self.fipsCompliant = try c.decodeIfPresent(Bool.self, forKey: .fipsCompliant) ?? false
    }
}

// MARK: - 언어 (단일 | 배열 | 맵)

public enum KSWiXLanguage: Codable, Sendable, Equatable {
    case single(String)
    case list([String])
    case map([String: KSWiXLanguageEntry])

    /// 평탄화된 언어 태그 목록 (순서 보존).
    public var tags: [String] {
        switch self {
        case .single(let s): return [s]
        case .list(let xs): return xs
        case .map(let m): return Array(m.keys).sorted()
        }
    }

    /// 해당 언어의 `.wxl` 로케일 파일 경로 (있는 경우).
    public func localePath(for tag: String) -> String? {
        if case .map(let m) = self {
            return m[tag]?.localePath
        }
        return nil
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .single(s)
            return
        }
        if let xs = try? c.decode([String].self) {
            self = .list(xs)
            return
        }
        if let m = try? c.decode([String: KSWiXLanguageEntry].self) {
            self = .map(m)
            return
        }
        throw DecodingError.typeMismatch(
            KSWiXLanguage.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected string, array of strings, or { lang: { localePath } } map"
            ))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .single(let s): try c.encode(s)
        case .list(let xs): try c.encode(xs)
        case .map(let m): try c.encode(m)
        }
    }
}

public struct KSWiXLanguageEntry: Codable, Sendable, Equatable {
    public var localePath: String?

    public init(localePath: String? = nil) {
        self.localePath = localePath
    }
}

// MARK: - WebView2 Runtime 설치 모드 (Tauri WebviewInstallMode 미러)

public enum KSWebView2InstallMode: Codable, Sendable, Equatable {
    /// 인스톨러가 WebView2 Runtime 설치를 시도하지 않음.
    case skip
    /// 부트스트래퍼(~2 MB)를 인터넷에서 받아 silent 실행.
    case downloadBootstrapper(silent: Bool)
    /// 부트스트래퍼(~1.8 MB)를 인스톨러에 임베드.
    case embedBootstrapper(silent: Bool)
    /// 오프라인 인스톨러(~127 MB)를 임베드.
    case offlineInstaller(silent: Bool)
    /// 고정 버전 Runtime(~180 MB)을 임베드. `path`는 추출된 Runtime 디렉터리.
    case fixedRuntime(path: String)

    private enum CodingKeys: String, CodingKey { case type, silent, path }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "skip":
            self = .skip
        case "downloadBootstrapper":
            self = .downloadBootstrapper(
                silent: try c.decodeIfPresent(Bool.self, forKey: .silent) ?? true)
        case "embedBootstrapper":
            self = .embedBootstrapper(
                silent: try c.decodeIfPresent(Bool.self, forKey: .silent) ?? true)
        case "offlineInstaller":
            self = .offlineInstaller(
                silent: try c.decodeIfPresent(Bool.self, forKey: .silent) ?? true)
        case "fixedRuntime":
            let p = try c.decode(String.self, forKey: .path)
            self = .fixedRuntime(path: p)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription:
                    "Unknown WebView2 install mode: \(type). Expected one of "
                    + "skip|downloadBootstrapper|embedBootstrapper|offlineInstaller|fixedRuntime")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .skip:
            try c.encode("skip", forKey: .type)
        case .downloadBootstrapper(let silent):
            try c.encode("downloadBootstrapper", forKey: .type)
            try c.encode(silent, forKey: .silent)
        case .embedBootstrapper(let silent):
            try c.encode("embedBootstrapper", forKey: .type)
            try c.encode(silent, forKey: .silent)
        case .offlineInstaller(let silent):
            try c.encode("offlineInstaller", forKey: .type)
            try c.encode(silent, forKey: .silent)
        case .fixedRuntime(let path):
            try c.encode("fixedRuntime", forKey: .type)
            try c.encode(path, forKey: .path)
        }
    }
}

// MARK: - 사이닝 명령 (Tauri CustomSignCommandConfig 미러)

public enum KSSignCommand: Codable, Sendable, Equatable {
    /// 단일 셸 명령 문자열. `%1` 또는 `{file}` 플레이스홀더로 대상 파일을 받는다.
    case string(String)
    /// 분리된 cmd/args. args 안의 `%1`/`{file}`이 치환된다.
    case command(cmd: String, args: [String])

    private enum CodingKeys: String, CodingKey { case cmd, args }

    public init(from decoder: any Decoder) throws {
        let single = try? decoder.singleValueContainer()
        if let s = try? single?.decode(String.self) {
            self = .string(s)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cmd = try c.decode(String.self, forKey: .cmd)
        let args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        self = .command(cmd: cmd, args: args)
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .string(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .command(let cmd, let args):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(cmd, forKey: .cmd)
            try c.encode(args, forKey: .args)
        }
    }
}
