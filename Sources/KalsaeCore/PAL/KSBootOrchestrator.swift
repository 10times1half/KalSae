public import Foundation

/// 부팅 단계의 순수 함수/헬퍼를 모아둔 네임스페이스.
///
/// `KSApp.boot(config:)` 와 각 플랫폼의 `runOnMain(...)` 모두 동일한
/// 결정 로직(윈도우 선택, 서빙 모드 결정, 시작 URL 해석, CSP 주입 스크립트
/// 생성)을 필요로 한다. 이 타입은 그 로직을 한 곳으로 모아 5개 플랫폼에
/// 흩어져 있던 fileprivate 복사본 + KSApp 의 정적 함수들을 단일 진실
/// 공급원으로 통일한다.
///
/// 모든 멤버는 `static` + 순수 함수다 — I/O 없음, 콜백 없음, 사이드이펙트
/// 없음. 부팅 흐름의 의사결정 가지(decision arms)만 캡슐화한다.
public enum KSBootOrchestrator {

    /// 프론트엔드 제공 방식 결정 결과.
    /// - `.virtualHost(root)` — `https://app.kalsae/`(Windows) 또는
    ///   `ks://app/`(macOS/Linux)로 로컬 자산 제공.
    /// - `.devServer` — `config.build.devServerURL` 로 직접 navigate.
    /// - `.fallback` — 가상 호스트도 dev 서버도 없음. 호출자가 진단 페이지
    ///   또는 dev URL 문자열로 폴백.
    public enum ServingMode: Sendable {
        case virtualHost(URL)
        case devServer
        case fallback
    }

    /// 부팅할 윈도우 설정을 선택한다.
    /// - `label` 이 주어지면 일치하는 항목을 반환.
    /// - `nil` 이면 설정에 선언된 첫 번째 윈도우를 반환.
    public static func selectWindow(
        from config: KSConfig, label: String? = nil
    ) throws(KSError) -> KSWindowConfig {
        if let label {
            guard let match = config.windows.first(where: { $0.label == label }) else {
                throw KSError.configInvalid("no window labelled '\(label)'")
            }
            return match
        }
        guard let first = config.windows.first else {
            throw KSError.configInvalid("config.windows is empty")
        }
        return first
    }

    /// 비어있지 않은 `http://` / `https://` URL 만 원격 dev 서버로 본다.
    /// 빈 문자열과 `about:blank` 은 "dev 서버 미설정" 으로 취급한다.
    public static func isRemoteURL(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.lowercased() == "about:blank" { return false }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// `url` 이 가리키는 경로가 디렉터리인지 검사한다.
    public static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// 서빙 모드를 결정한다. 호출자(`KSApp.boot` 또는 platform `runOnMain`)는
    /// 자신의 지식 범위에 맞춰 다음 인자를 주입한다:
    /// - `urlOverride`: 호출자가 명시적으로 지정한 시작 URL (있으면 dev 서버
    ///   자동 분기 차단).
    /// - `windowURL`: `KSWindowConfig.url` 값.
    /// - `devServerURL`: `KSConfig.build.devServerURL`.
    /// - `resourceRoot`: 가상 호스트로 서빙할 자산 디렉터리. `nil` 또는
    ///   존재하지 않으면 dev/fallback 경로로 떨어진다.
    /// - `isDevServerReachable`: dev 서버 reachability 확인 콜백. `nil` 이면
    ///   reachability 검사를 생략하고 `devIsRemote` 만 보고 `.devServer` 를
    ///   고른다(플랫폼 `runOnMain` 의 단순 동작).
    /// - `preferEmbeddedAssets`: Windows-specific. `true` 면 `resourceRoot`
    ///   가 없거나 비-디렉터리여도 가상 호스트로 강제(임베디드 자산 리졸버
    ///   사용).
    public static func decideServingMode(
        urlOverride: String? = nil,
        windowURL: String?,
        devServerURL: String,
        resourceRoot: URL?,
        isDevServerReachable: ((String) -> Bool)? = nil,
        preferEmbeddedAssets: Bool = false
    ) -> ServingMode {
        let devIsRemote = isRemoteURL(devServerURL)
        if urlOverride == nil, windowURL == nil, devIsRemote {
            if let probe = isDevServerReachable {
                if probe(devServerURL) {
                    return .devServer
                }
                // probe 실패 → 가상 호스트/폴백으로 떨어진다.
            } else {
                return .devServer
            }
        }
        if let resourceRoot, isDirectory(resourceRoot) {
            return .virtualHost(resourceRoot)
        }
        if preferEmbeddedAssets {
            return .virtualHost(resourceRoot ?? URL(fileURLWithPath: "."))
        }
        return .fallback
    }

    /// 윈도우에 로드할 실제 URL 문자열을 결정한다. 우선순위:
    /// 호출별 오버라이드 → 윈도우별 URL → 가상 호스트 기본값
    /// → 라이브 dev 서버 → fallback.
    ///
    /// `fallbackURL` 인자는 `.fallback` 모드에서 사용할 문자열을 지정한다.
    /// `KSApp.boot` 는 진단 `data:` URL 을 넘기고, 플랫폼 `runOnMain` 은
    /// `devServerURL` 을 그대로 넘긴다(레거시 동작 유지).
    public static func resolveStartURL(
        urlOverride: String? = nil,
        windowURL: String?,
        devServerURL: String,
        servingMode: ServingMode,
        virtualHostURL: String,
        fallbackURL: String? = nil
    ) -> String {
        if let urlOverride { return urlOverride }
        if let windowURL { return windowURL }
        switch servingMode {
        case .virtualHost:
            return virtualHostURL
        case .devServer:
            return devServerURL
        case .fallback:
            return fallbackURL ?? devServerURL
        }
    }

    /// CSP `<meta>` 태그를 가능한 빨리(문서 파싱 전) 주입하는 JS 스크립트.
    /// 플랫폼 호스트는 이를 document-created script 로 등록한다.
    public static func cspInjectionScript(_ csp: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(csp.count + 8)
        for ch in csp {
            switch ch {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            default: escaped.append(ch)
            }
        }
        return """
            (function(){
            var csp = "\(escaped)";
            function install() {
            if (!document.head && document.documentElement) {
            var h = document.createElement('head');
            document.documentElement.insertBefore(h, document.documentElement.firstChild);
            }
            if (!document.head) { return false; }
            var meta = document.createElement('meta');
            meta.httpEquiv = 'Content-Security-Policy';
            meta.content = csp;
            document.head.insertBefore(meta, document.head.firstChild);
            return true;
            }
            if (!install()) {
            var obs = new MutationObserver(function(_, o){
            if (install()) { o.disconnect(); }
            });
            obs.observe(document, {childList:true, subtree:true});
            }
            })();
            """
    }
}
