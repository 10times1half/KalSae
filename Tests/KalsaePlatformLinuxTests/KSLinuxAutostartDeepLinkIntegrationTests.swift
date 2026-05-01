#if os(Linux)
import Testing
import Foundation
internal import Glibc
@testable import KalsaePlatformLinux
import KalsaeCore

@Suite("KSLinux Autostart/DeepLink — integration contract", .serialized)
struct KSLinuxAutostartDeepLinkIntegrationTests {

    @Test("autostart enable/disable toggles isEnabled and writes desktop file")
    func autostartEnableDisableCycle() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ks-autostart-\(UUID().uuidString)")
        let xdgConfigHome = tempRoot.path
        let identifier = "dev.kalsae.test.autostart.\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        _ = setenv("XDG_CONFIG_HOME", xdgConfigHome, 1)
        defer {
            _ = unsetenv("XDG_CONFIG_HOME")
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let backend = KSLinuxAutostartBackend(identifier: identifier)
        let desktopPath = tempRoot
            .appendingPathComponent("autostart")
            .appendingPathComponent("\(identifier).desktop")

        #expect(backend.isEnabled() == false)

        try backend.enable()
        #expect(backend.isEnabled())
        #expect(FileManager.default.fileExists(atPath: desktopPath.path))

        let content = try String(contentsOf: desktopPath, encoding: .utf8)
        #expect(content.contains("[Desktop Entry]"))
        #expect(content.contains("Name=\(identifier)"))

        try backend.disable()
        #expect(backend.isEnabled() == false)
        #expect(FileManager.default.fileExists(atPath: desktopPath.path) == false)
    }

    @Test("deep-link register/unregister creates and removes desktop file")
    func deepLinkRegisterUnregisterCycle() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ks-deeplink-\(UUID().uuidString)")
        let xdgDataHome = tempRoot.path
        let identifier = "dev.kalsae.test.deeplink.\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let scheme = "kalsae-itest"

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        _ = setenv("XDG_DATA_HOME", xdgDataHome, 1)
        defer {
            _ = unsetenv("XDG_DATA_HOME")
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let backend = KSLinuxDeepLinkBackend(identifier: identifier)
        let desktopPath = tempRoot
            .appendingPathComponent("applications")
            .appendingPathComponent("\(identifier).\(scheme).desktop")

        try backend.register(scheme: scheme)
        #expect(FileManager.default.fileExists(atPath: desktopPath.path))

        let content = try String(contentsOf: desktopPath, encoding: .utf8)
        #expect(content.contains("MimeType=x-scheme-handler/\(scheme);"))
        #expect(content.contains("Exec="))

        try backend.unregister(scheme: scheme)
        #expect(FileManager.default.fileExists(atPath: desktopPath.path) == false)
    }

    @Test("deep-link register rejects invalid scheme")
    func deepLinkRejectsInvalidScheme() {
        let backend = KSLinuxDeepLinkBackend(identifier: "dev.kalsae.test.invalid")

        do {
            try backend.register(scheme: "bad://scheme")
            Issue.record("Expected configInvalid for malformed scheme")
        } catch let error {
            #expect(error.code == .configInvalid)
        }
    }

    @Test("deep-link extractURLs filters by scheme and URL shape")
    func deepLinkExtractURLsContract() {
        let backend = KSLinuxDeepLinkBackend(identifier: "dev.kalsae.test.extract")
        let args = [
            "kalsae://open?id=1",
            "KALSAE://upper",
            "https://example.com",
            "not-a-url",
            "other://x"
        ]

        let filtered = backend.extractURLs(fromArgs: args, forSchemes: ["kalsae"])
        #expect(filtered.count == 2)
        #expect(filtered.contains("kalsae://open?id=1"))
        #expect(filtered.contains("KALSAE://upper"))
    }
}
#endif
