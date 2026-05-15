import Foundation
import KalsaeCore
import Testing

@testable import KalsaeCLICore

@Suite("KSCapabilityValidator")
struct CapabilityValidatorTests {

    private func makeConfig(
        permissions: [KSPermission] = [],
        capabilities: [KSCapability] = []
    ) -> KSCapabilitiesConfig {
        KSCapabilitiesConfig(permissions: permissions, capabilities: capabilities)
    }

    @Test("Empty config produces no findings")
    func emptyConfig() {
        let report = KSCapabilityValidator.validate(
            capabilities: makeConfig(), commands: [])
        #expect(report.findings.isEmpty)
        #expect(!report.shouldFail(in: .strict))
    }

    @Test("Capability referencing unknown permission yields error")
    func unknownPermissionRef() {
        let caps = makeConfig(
            permissions: [KSPermission(identifier: "fs:read", commandsAllow: ["fs.*"])],
            capabilities: [
                KSCapability(
                    identifier: "main",
                    windows: ["main"],
                    permissions: ["fs:write"])
            ])
        let report = KSCapabilityValidator.validate(capabilities: caps, commands: [])
        #expect(report.errors.contains { $0.code == "unknown_permission" })
        #expect(report.shouldFail(in: .warn))
    }

    @Test("Duplicate identifiers reported")
    func duplicates() {
        let caps = makeConfig(
            permissions: [
                KSPermission(identifier: "fs:read"),
                KSPermission(identifier: "fs:read"),
            ],
            capabilities: [
                KSCapability(identifier: "main", permissions: []),
                KSCapability(identifier: "main", permissions: []),
            ])
        let report = KSCapabilityValidator.validate(capabilities: caps, commands: [])
        #expect(report.errors.contains { $0.code == "duplicate_permission" })
        #expect(report.errors.contains { $0.code == "duplicate_capability" })
    }

    @Test("Wildcard usage produces warnings, not errors")
    func wildcardWarnings() {
        let caps = makeConfig(
            permissions: [
                KSPermission(identifier: "all", commandsAllow: ["*"])
            ],
            capabilities: [
                KSCapability(identifier: "main", windows: ["*"], permissions: ["all"])
            ])
        let report = KSCapabilityValidator.validate(capabilities: caps, commands: [])
        #expect(report.errors.isEmpty)
        #expect(report.warnings.contains { $0.code == "wildcard_commands_allow" })
        #expect(report.warnings.contains { $0.code == "wildcard_windows" })
        // warn mode shouldn't fail when only warnings are present
        #expect(!report.shouldFail(in: .warn))
        // strict mode fails on any finding
        #expect(report.shouldFail(in: .strict))
    }

    @Test("Command referencing missing permission yields error")
    func commandPermissionMissing() {
        let caps = makeConfig(
            permissions: [KSPermission(identifier: "fs:read")],
            capabilities: [])
        let cmd = KSCapabilityValidator.CommandInfo(
            name: "fs.write", permission: "fs:write")
        let report = KSCapabilityValidator.validate(
            capabilities: caps, commands: [cmd])
        #expect(
            report.errors.contains { $0.code == "command_permission_not_in_catalog" })
    }

    @Test("Command without permission attribute is ignored")
    func commandWithoutPermissionIgnored() {
        let caps = makeConfig(permissions: [], capabilities: [])
        let cmd = KSCapabilityValidator.CommandInfo(name: "foo", permission: nil)
        let report = KSCapabilityValidator.validate(
            capabilities: caps, commands: [cmd])
        #expect(report.findings.isEmpty)
    }

    @Test("off mode never fails")
    func offModeNeverFails() {
        let caps = makeConfig(
            permissions: [],
            capabilities: [
                KSCapability(
                    identifier: "main", windows: ["main"], permissions: ["missing"])
            ])
        let report = KSCapabilityValidator.validate(capabilities: caps, commands: [])
        #expect(!report.errors.isEmpty)
        #expect(!report.shouldFail(in: .off))
    }
}
