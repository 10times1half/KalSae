import Foundation
import KalsaeCore
import Testing

@Suite("KSUUIDv5 — RFC 4122 §4.3 vectors")
struct KSUUIDv5Tests {

    /// RFC 4122 Appendix B (Errata-adjusted) widely-used vector:
    /// uuid_v5(DNS, "python.org") == 886313e1-3b8a-5372-9b90-0c9aee199e5d
    @Test("python.org in DNS namespace matches golden vector")
    func pythonOrgVector() {
        let u = KSUUIDv5.v5(namespace: KSUUIDv5.dnsNamespace, name: "python.org")
        #expect(KSUUIDv5.format(u).lowercased() == "886313e1-3b8a-5372-9b90-0c9aee199e5d")
    }

    @Test("wixUpgradeCode is deterministic for same inputs")
    func deterministicUpgradeCode() {
        let a = KSUUIDv5.wixUpgradeCode(productName: "MyApp", arch: "x64")
        let b = KSUUIDv5.wixUpgradeCode(productName: "MyApp", arch: "x64")
        #expect(a == b)
    }

    @Test("wixUpgradeCode differs by arch")
    func archAffects() {
        let a = KSUUIDv5.wixUpgradeCode(productName: "MyApp", arch: "x64")
        let b = KSUUIDv5.wixUpgradeCode(productName: "MyApp", arch: "arm64")
        #expect(a != b)
    }

    @Test("format produces uppercase hyphenated 36-char string")
    func formatShape() {
        let u = KSUUIDv5.v5(namespace: KSUUIDv5.dnsNamespace, name: "kalsae.dev")
        let s = KSUUIDv5.format(u)
        #expect(s.count == 36)
        #expect(s == s.uppercased())
        #expect(s.filter { $0 == "-" }.count == 4)
    }
}
