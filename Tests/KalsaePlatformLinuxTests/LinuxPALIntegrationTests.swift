#if os(Linux)
import Testing
import Foundation
@testable import KalsaePlatformLinux
import KalsaeCore

@Suite("KSLinuxPlatform — init & backend wiring")
struct KSLinuxPlatformInitTests {

    @Test("All PAL backend properties return correct concrete types")
    func backendTypesAreCorrect() {
        let platform = KSLinuxPlatform()
        #expect(platform.windows is KSLinuxWindowBackend)
        #expect(platform.dialogs is KSLinuxDialogBackend)
        #expect(platform.menus is KSLinuxMenuBackend)
        #expect(platform.notifications is KSLinuxNotificationBackend)
        #expect((platform.tray as? KSLinuxTrayBackend) != nil)
        #expect((platform.shell as? KSLinuxShellBackend) != nil)
        #expect((platform.clipboard as? KSLinuxClipboardBackend) != nil)
        #expect((platform.accelerators as? KSLinuxAcceleratorBackend) != nil)
    }

    @Test("commandRegistry wiring — register and dispatch round-trip")
    func commandRegistryRoundTrip() async {
        let platform = KSLinuxPlatform()
        let registry = platform.commandRegistry
        await registry.register("ks.test.echo") { data in .success(data) }

        let payload = Data("hello-linux".utf8)
        let result = await registry.dispatch(name: "ks.test.echo", args: payload)
        switch result {
        case .success(let data):
            #expect(data == payload)
        case .failure(let error):
            Issue.record("Echo command must succeed: \(error)")
        }
    }
}

@Suite("KSLinuxWindowBackend — unit contract (no GTK window)")
struct KSLinuxWindowBackendUnitTests {

    let backend = KSLinuxWindowBackend()

    @Test("webView(for:) throws windowCreationFailed for unknown handle")
    func webViewForMissingHandle() async {
        let handle = KSWindowHandle(label: "ks-test-linux-ghost-wv", rawValue: 0)
        do {
            _ = try await backend.webView(for: handle)
            Issue.record("Expected windowCreationFailed to be thrown")
        } catch let error {
            #expect(error.code == .windowCreationFailed,
                    "Expected windowCreationFailed, got \(error.code)")
        }
    }

    @Test("show() throws windowCreationFailed for unknown handle")
    func showMissingHandle() async {
        let handle = KSWindowHandle(label: "ks-test-linux-ghost-show", rawValue: 0)
        do {
            try await backend.show(handle)
            Issue.record("Expected windowCreationFailed to be thrown")
        } catch let error {
            #expect(error.code == .windowCreationFailed,
                    "Expected windowCreationFailed, got \(error.code)")
        }
    }

    @Test("find(label:) returns nil for unknown label")
    func findUnknownLabel() async {
        let label = "ks-test-linux-nonexistent-\(UInt64.random(in: 1...UInt64.max))"
        let result = await backend.find(label: label)
        #expect(result == nil)
    }
}

@Suite("KSLinux PAL stubs and clipboard no-host contract")
struct KSLinuxPALStubContractTests {

    @Test("tray install/setTooltip/setMenu throw unsupportedPlatform")
    func trayMethodsAreUnsupported() async {
        let backend = KSLinuxTrayBackend()

        do {
            try await backend.install(KSTrayConfig(icon: "tray.png"))
            Issue.record("Expected unsupportedPlatform from tray.install")
        } catch let error {
            #expect(error.code == .unsupportedPlatform)
        }

        do {
            try await backend.setTooltip("tip")
            Issue.record("Expected unsupportedPlatform from tray.setTooltip")
        } catch let error {
            #expect(error.code == .unsupportedPlatform)
        }

        do {
            try await backend.setMenu([])
            Issue.record("Expected unsupportedPlatform from tray.setMenu")
        } catch let error {
            #expect(error.code == .unsupportedPlatform)
        }
    }

    @Test("accelerator protocol defaults throw unsupportedPlatform")
    func acceleratorMethodsAreUnsupported() async {
        let backend = KSLinuxAcceleratorBackend()

        do {
            try await backend.register(id: "accel-1", accelerator: "Ctrl+K") {}
            Issue.record("Expected unsupportedPlatform from accelerator.register")
        } catch let error {
            #expect(error.code == .unsupportedPlatform)
        }

        do {
            try await backend.unregister(id: "accel-1")
            Issue.record("Expected unsupportedPlatform from accelerator.unregister")
        } catch let error {
            #expect(error.code == .unsupportedPlatform)
        }

        do {
            try await backend.unregisterAll()
            Issue.record("Expected unsupportedPlatform from accelerator.unregisterAll")
        } catch let error {
            #expect(error.code == .unsupportedPlatform)
        }
    }

    @Test("clipboard no-host path returns nil/false or throws unsupportedPlatform")
    func clipboardNoHostContract() async {
        let backend = KSLinuxClipboardBackend()

        let text = try? await backend.readText()
        #expect(text == nil)

        let image = try? await backend.readImage()
        #expect(image == nil)

        let hasText = await backend.hasFormat("text")
        #expect(!hasText)

        do {
            try await backend.writeText("hello")
            Issue.record("Expected unsupportedPlatform from clipboard.writeText")
        } catch let error {
            #expect(error.code == .unsupportedPlatform)
        }

        do {
            try await backend.writeImage(Data([0x89, 0x50, 0x4E, 0x47]))
            Issue.record("Expected unsupportedPlatform from clipboard.writeImage")
        } catch let error {
            #expect(error.code == .unsupportedPlatform)
        }

        do {
            try await backend.clear()
            Issue.record("Expected unsupportedPlatform from clipboard.clear")
        } catch let error {
            #expect(error.code == .unsupportedPlatform)
        }
    }
}
#endif
