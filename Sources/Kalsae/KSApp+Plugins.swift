public import KalsaeCore

// MARK: - 플러그인 설치

extension KSApp {
    /// 부팅 완료 후 플러그인 배열을 한 번에 설치한다.
    ///
    /// `KSApp.boot(...)` 반환 후, `run()` 호출 전에 사용한다:
    /// ```swift
    /// let app = try await KSApp.boot(configURL: ...) { _ in }
    /// try await app.install([AnalyticsPlugin(), FooPlugin()])
    /// exit(app.run())
    /// ```
    ///
    /// 동작 순서:
    /// 1. 각 플러그인의 `namespace` 검증 (빈 문자열/공백/`__ks.` prefix 거부)
    /// 2. 중복 namespace 거부
    /// 3. `commandAllowlist`가 설정된 경우, 해당 namespace를 허용하지 않으면 경고 로그 출력
    /// 4. 순차적으로 `plugin.setup(ctx)` 호출
    /// 5. 내부 목록에 저장 — `shutdown()` 시 역순으로 `teardown(ctx)` 호출됨
    ///
    /// 설치 도중 하나가 throw하면 그 이전에 등록된 명령은 레지스트리에 남는다.
    /// 롤백은 지원하지 않는다.
    public func install(_ plugins: [any KSPlugin]) async throws(KSError) {
        let ctx = DefaultPluginContext(app: self)

        // 1+2. 네임스페이스 검증 및 중복 체크
        var seen: Set<String> = []
        for plugin in plugins {
            let ns = type(of: plugin).namespace
            try ksValidatePluginNamespace(ns)
            guard seen.insert(ns).inserted else {
                throw KSError.configInvalid(
                    "duplicate plugin namespace '\(ns)'")
            }
        }

        // 3. commandAllowlist 경고
        if let allowlist = config.security.commandAllowlist {
            let allowedSet = Set(allowlist)
            for plugin in plugins {
                let ns = type(of: plugin).namespace
                let covered = allowedSet.contains(where: { $0.hasPrefix(ns) || $0 == ns })
                if !covered {
                    let log = KSLog.logger("kalsae.plugin")
                    log.warning(
                        "plugin '\(ns)' commands may be blocked: no matching entry in commandAllowlist. Add '\(ns).*' or specific command names to kalsae.json security.commandAllowlist."
                    )
                }
            }
        }

        // 4. 순차 setup
        for plugin in plugins {
            try await plugin.setup(ctx)
        }

        // 5. teardown을 위해 목록에 추가
        _plugins.append(contentsOf: plugins)
    }
}

// MARK: - KSApp 플러그인 저장소

extension KSApp {
    /// 현재 설치된 플러그인 목록 — teardown 순서 보장을 위해 보유한다.
    var _plugins: [any KSPlugin] {
        get { _pluginsStorage }
        set { _pluginsStorage = newValue }
    }
}

// MARK: - DefaultPluginContext

/// `KSPlugin`에 전달되는 구체적인 컨텍스트 구현.
/// `KSApp`을 직접 노출하지 않고 최소 표면만 제공한다.
internal struct DefaultPluginContext: KSPluginContext {
    private let app: KSApp

    init(app: KSApp) {
        self.app = app
    }

    var registry: KSCommandRegistry { app.registry }
    var platform: any KSPlatform { app.platform }

    func emit(_ event: String, payload: sending any Encodable) async throws(KSError) {
        do {
            try await MainActor.run { try app.emit(event, payload: payload) }
        } catch let e as KSError {
            throw e
        } catch {
            throw KSError(code: .internal, message: error.localizedDescription)
        }
    }
}
