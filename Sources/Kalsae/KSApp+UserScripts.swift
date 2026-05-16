/// 사용자 스크립트(`KSUserScript`)를 등록하기 위한 `KSApp` 표면.
///
/// Tauri v2의 `initialization_script`에 대응한다. 모든 등록은 다음 두 단계를 거친다:
///   1. `KSSecurityConfig.userScripts.allowOrigins` 화이트리스트 검사(default-deny).
///   2. `KSUserScriptWrapper`로 origin 가드/documentEnd 폴리필/예외 격리 IIFE로 래핑.
///   3. PAL DemoHost (`KSDemoHostWithUserScripts`)에 documentStart 시점 주입 등록.
///
/// 런타임 추가는 **다음 navigation부터 적용**된다. 현재 페이지에는 영향을 주지 않는다.
public import Foundation
public import KalsaeCore

extension KSApp {
    /// 사용자 스크립트를 등록한다.
    /// - `script.id`가 비어 있으면 UUID로 자동 채워진다.
    /// - 동일한 `id`가 이미 등록되어 있으면 `KSError.configInvalid`를 던진다.
    /// - 모든 `script.origins`는 `security.userScripts.allowOrigins`의 부분집합이어야 한다.
    /// - `script.source`와 `script.path` 중 정확히 하나만 지정해야 한다.
    /// - `path`는 `resourceRoot`(또는 `build.dist`) 상대 경로이며 `..` 트래버설을 금지한다.
    ///
    /// - Returns: 자동 채워진 경우를 포함한 최종 스크립트 `id`. 호출자는 향후
    ///   진단/로그에 사용할 수 있다(개별 제거는 v0.x 범위 밖).
    @discardableResult
    public func addUserScript(_ script: KSUserScript) throws(KSError) -> String {
        var s = script
        if s.id.isEmpty {
            s.id = "user-" + UUID().uuidString.lowercased()
        }
        try Self.validateUserScript(s, against: config.security.userScripts)
        guard _registeredUserScriptIDs.insert(s.id).inserted else {
            throw KSError.configInvalid(
                "user script id '\(s.id)' is already registered")
        }
        let resolvedSource = try Self.resolveSource(for: s, resourceRoot: _userScriptResourceRoot)
        let wrapped = KSUserScriptWrapper.wrap(s, source: resolvedSource)
        guard let userScriptHost = _userScriptHost else {
            // 부팅 이전에 호출될 수 있음 — 큐잉하지 않고 즉시 오류.
            throw KSError.configInvalid(
                "addUserScript called before boot completed")
        }
        try userScriptHost.addUserScript(
            id: s.id, wrappedSource: wrapped, forMainFrameOnly: s.forMainFrameOnly)
        return s.id
    }

    // MARK: - Internal (called by KSApp+Boot)

    /// Boot 시 `KSSecurityConfig.userScripts.scripts`를 일괄 등록한다.
    /// 각 호스트(primary + secondary)별로 한 번씩 호출된다. CSP 주입 직후 시점.
    static func installDeclaredUserScripts(
        on host: any KSDemoHostWithUserScripts,
        scope: KSUserScriptsScope,
        resourceRoot: URL?
    ) throws(KSError) {
        for script in scope.scripts {
            var s = script
            if s.id.isEmpty {
                s.id = "config-" + UUID().uuidString.lowercased()
            }
            try validateUserScript(s, against: scope)
            let resolvedSource = try resolveSource(for: s, resourceRoot: resourceRoot)
            let wrapped = KSUserScriptWrapper.wrap(s, source: resolvedSource)
            try host.addUserScript(
                id: s.id, wrappedSource: wrapped, forMainFrameOnly: s.forMainFrameOnly)
        }
    }

    /// Boot가 어느 host와 어느 resourceRoot에 user-script를 라우팅할지 KSApp에 알려준다.
    func bindUserScriptHost(_ host: any KSDemoHostWithUserScripts, resourceRoot: URL?) {
        _userScriptHost = host
        _userScriptResourceRoot = resourceRoot
        // Config 선언 ID들을 dedupe 셋에 미리 채운다.
        for s in config.security.userScripts.scripts where !s.id.isEmpty {
            _registeredUserScriptIDs.insert(s.id)
        }
    }

    // MARK: - Helpers

    private static func validateUserScript(
        _ s: KSUserScript,
        against scope: KSUserScriptsScope
    ) throws(KSError) {
        if scope.allowOrigins.isEmpty {
            throw KSError.permissionDenied(
                command: "addUserScript",
                reason: "security.userScripts.allowOrigins is empty (default-deny)",
                capability: "userScripts")
        }
        let hasSource = (s.source?.isEmpty == false)
        let hasPath = (s.path?.isEmpty == false)
        if hasSource == hasPath {
            throw KSError.configInvalid(
                "KSUserScript must specify exactly one of 'source' or 'path'")
        }
        if let p = s.path, hasPath {
            if p.contains("..") || p.hasPrefix("/") || p.hasPrefix("\\") {
                throw KSError.configInvalid(
                    "KSUserScript.path must be relative resourceRoot path without '..'")
            }
        }
        if s.origins.isEmpty {
            throw KSError.configInvalid("KSUserScript.origins must not be empty")
        }
        for o in s.origins {
            if !scope.permits(originPattern: o) {
                throw KSError.permissionDenied(
                    command: "addUserScript",
                    reason: "origin '\(o)' is not in security.userScripts.allowOrigins",
                    capability: "userScripts")
            }
        }
    }

    private static func resolveSource(
        for s: KSUserScript,
        resourceRoot: URL?
    ) throws(KSError) -> String {
        if let src = s.source, !src.isEmpty {
            return src
        }
        guard let p = s.path, !p.isEmpty else {
            throw KSError.configInvalid("KSUserScript has no source or path")
        }
        guard let root = resourceRoot else {
            throw KSError.configInvalid(
                "KSUserScript.path '\(p)' cannot be resolved: no resourceRoot bound")
        }
        let fileURL = root.appendingPathComponent(p)
        // 추가 안전: 정규화 후 root 외부로 나가지 않는지 검사.
        let rootResolved = root.standardizedFileURL.path
        let resolved = fileURL.standardizedFileURL.path
        if !resolved.hasPrefix(rootResolved) {
            throw KSError.configInvalid(
                "KSUserScript.path '\(p)' escapes resourceRoot")
        }
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw KSError.configInvalid(
                "failed to read KSUserScript.path '\(p)': \(error.localizedDescription)")
        }
    }
}

// MARK: - 인스턴스 상태 저장

// 확장에서 stored property를 가질 수 없으므로 KSApp의 본체에 약 참조 박스를
// 두는 대신, 키-별 ObjectIdentifier 디스패치를 사용한다. KSApp은 `@MainActor`
// 이므로 정적 가변 상태에 동기 접근이 안전하다.

@MainActor
private final class _UserScriptHostBox {
    weak var host: AnyObject?
    var resourceRoot: URL?
}

@MainActor
private var _userScriptBoxes: [ObjectIdentifier: _UserScriptHostBox] = [:]

extension KSApp {
    fileprivate var _userScriptHost: (any KSDemoHostWithUserScripts)? {
        get {
            _userScriptBoxes[ObjectIdentifier(self)]?.host
                as? any KSDemoHostWithUserScripts
        }
        set {
            let key = ObjectIdentifier(self)
            let box = _userScriptBoxes[key] ?? _UserScriptHostBox()
            box.host = newValue as AnyObject?
            _userScriptBoxes[key] = box
        }
    }

    fileprivate var _userScriptResourceRoot: URL? {
        get { _userScriptBoxes[ObjectIdentifier(self)]?.resourceRoot }
        set {
            let key = ObjectIdentifier(self)
            let box = _userScriptBoxes[key] ?? _UserScriptHostBox()
            box.resourceRoot = newValue
            _userScriptBoxes[key] = box
        }
    }
}
