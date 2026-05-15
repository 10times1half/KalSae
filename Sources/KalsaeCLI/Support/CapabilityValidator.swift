import Foundation
public import KalsaeCore

/// `kalsae.json`의 capability/permission 정책과 `@KSCommand` 소스 사이의
/// 일관성을 검증한다.
///
/// CLI에서 `kalsae build` / `kalsae generate bindings` 등이 빌드 전에
/// 실행하며, 다음과 같은 문제를 진단한다:
///   - capability가 카탈로그에 없는 권한 식별자를 참조 (오류)
///   - 권한/capability 식별자 중복 (오류)
///   - `@KSCommand(permission:)` 함수가 참조하는 권한이 카탈로그에 없음 (오류)
///   - `commandsAllow`/`commandsDeny`의 `"*"` 와일드카드 (경고)
///   - capability `windows`의 `"*"` 와일드카드 (경고)
public enum KSCapabilityValidator {
    /// 검증 시 발견된 단일 문제 항목.
    public struct Finding: Sendable, Equatable, CustomStringConvertible {
        public enum Severity: String, Sendable {
            case error
            case warning
        }
        public let severity: Severity
        public let code: String
        public let message: String

        public var description: String {
            "[\(severity.rawValue)] \(code): \(message)"
        }
    }

    /// 동작 모드. `kalsae.json`의 `security.policy` 등과는 독립적인
    /// CLI 차원의 검증 정책이다.
    public enum Mode: String, Sendable {
        /// 어떤 finding이라도 발견되면 빌드를 중단한다 (error+warning 모두 fail).
        case strict
        /// error는 fail, warning은 로그만 (기본값).
        case warn
        /// 검증 자체를 건너뛴다.
        case off
    }

    public struct Report: Sendable, CustomStringConvertible {
        public let findings: [Finding]
        public var errors: [Finding] { findings.filter { $0.severity == .error } }
        public var warnings: [Finding] { findings.filter { $0.severity == .warning } }

        public var description: String {
            if findings.isEmpty {
                return "capability validator: no issues found."
            }
            return findings.map(\.description).joined(separator: "\n")
        }

        /// `mode`에 따라 빌드 중단 여부를 결정한다.
        public func shouldFail(in mode: Mode) -> Bool {
            switch mode {
            case .off: return false
            case .warn: return !errors.isEmpty
            case .strict: return !findings.isEmpty
            }
        }
    }

    /// 소스에서 발견된 `@KSCommand` 함수 한 건의 검증용 요약.
    public struct CommandInfo: Sendable, Equatable {
        public let name: String
        public let permission: String?
        public init(name: String, permission: String?) {
            self.name = name
            self.permission = permission
        }
    }

    /// 검증을 실행한다.
    ///
    /// - Parameters:
    ///   - capabilities: `kalsae.json`의 capabilities 섹션. `nil`이면
    ///     레거시 정책만 사용하는 프로젝트로 간주되어 명령 단위 검증만 수행한다.
    ///   - commands: 소스에서 수집된 `@KSCommand` 함수 목록.
    public static func validate(
        capabilities: KSCapabilitiesConfig?,
        commands: [CommandInfo]
    ) -> Report {
        var findings: [Finding] = []

        if let caps = capabilities {
            findings.append(contentsOf: checkDuplicateIdentifiers(caps))
            findings.append(contentsOf: checkPermissionReferences(caps))
            findings.append(contentsOf: checkWildcardUsage(caps))
            findings.append(contentsOf: checkCommandPermissions(caps, commands: commands))
        }

        return Report(findings: findings)
    }

    // MARK: - Checks

    private static func checkDuplicateIdentifiers(
        _ caps: KSCapabilitiesConfig
    ) -> [Finding] {
        var findings: [Finding] = []
        var seenPerm = Set<String>()
        for p in caps.permissions {
            if !seenPerm.insert(p.identifier).inserted {
                findings.append(
                    Finding(
                        severity: .error,
                        code: "duplicate_permission",
                        message:
                            "Permission identifier '\(p.identifier)' is declared more than once."))
            }
        }
        var seenCap = Set<String>()
        for c in caps.capabilities {
            if !seenCap.insert(c.identifier).inserted {
                findings.append(
                    Finding(
                        severity: .error,
                        code: "duplicate_capability",
                        message:
                            "Capability identifier '\(c.identifier)' is declared more than once."))
            }
        }
        return findings
    }

    private static func checkPermissionReferences(
        _ caps: KSCapabilitiesConfig
    ) -> [Finding] {
        let catalog = Set(caps.permissions.map(\.identifier))
        var findings: [Finding] = []
        for cap in caps.capabilities {
            for ref in cap.permissions where !catalog.contains(ref) {
                findings.append(
                    Finding(
                        severity: .error,
                        code: "unknown_permission",
                        message:
                            "Capability '\(cap.identifier)' references unknown permission '\(ref)'."))
            }
        }
        return findings
    }

    private static func checkWildcardUsage(
        _ caps: KSCapabilitiesConfig
    ) -> [Finding] {
        var findings: [Finding] = []
        for p in caps.permissions {
            if p.commandsAllow.contains("*") {
                findings.append(
                    Finding(
                        severity: .warning,
                        code: "wildcard_commands_allow",
                        message:
                            "Permission '\(p.identifier)' allows all commands via '*' — narrow this for stronger isolation."
                    ))
            }
            if p.commandsDeny.contains("*") {
                findings.append(
                    Finding(
                        severity: .warning,
                        code: "wildcard_commands_deny",
                        message:
                            "Permission '\(p.identifier)' denies all commands via '*'."))
            }
        }
        for c in caps.capabilities {
            if c.windows.contains("*") {
                findings.append(
                    Finding(
                        severity: .warning,
                        code: "wildcard_windows",
                        message:
                            "Capability '\(c.identifier)' applies to all windows via '*' — consider listing labels explicitly."
                    ))
            }
        }
        return findings
    }

    private static func checkCommandPermissions(
        _ caps: KSCapabilitiesConfig,
        commands: [CommandInfo]
    ) -> [Finding] {
        let catalog = Set(caps.permissions.map(\.identifier))
        var findings: [Finding] = []
        for cmd in commands {
            guard let perm = cmd.permission else { continue }
            if !catalog.contains(perm) {
                findings.append(
                    Finding(
                        severity: .error,
                        code: "command_permission_not_in_catalog",
                        message:
                            "@KSCommand '\(cmd.name)' declares permission '\(perm)' which is not defined in capabilities.permissions."
                    ))
            }
        }
        return findings
    }
}
