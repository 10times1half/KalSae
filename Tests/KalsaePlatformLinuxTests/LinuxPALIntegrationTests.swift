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

    @Test("tray install/setTooltip/setMenu best-effort: never throw")
    func trayMethodsBestEffort() async {
        let backend = await KSLinuxTrayBackend()

        // install은 watcher 부재 시에도 throw하지 않고 경고만 남긴다.
        // CI / 헤드리스 환경에서는 D-Bus 세션이 없을 수 있어 platformInitFailed
        // (ks_gtk_tray_new 실패는 없음, 세션 버스 부재는 install 내부에서 폴백).
        do {
            try await backend.install(KSTrayConfig(icon: "tray.png"))
        } catch {
            // best-effort 경계 — 환경 한계로 인한 실패는 허용.
        }
        try? await backend.setTooltip("tip")
        try? await backend.setMenu([])
        await backend.remove()
    }

    @Test("accelerator without active host throws platformInitFailed; no-op for unregister")
    func acceleratorRequiresActiveHost() async {
        let backend = await KSLinuxAcceleratorBackend()

        do {
            try await backend.register(id: "accel-1", accelerator: "Ctrl+K") {}
            Issue.record("Expected platformInitFailed without active window")
        } catch let error {
            #expect(error.code == .platformInitFailed
                 || error.code == .invalidArgument)
        }

        // unregister/unregisterAll without a running window is a no-op.
        try? await backend.unregister(id: "accel-1")
        try? await backend.unregisterAll()
    }

    @Test("accelerator parser produces GTK trigger strings")
    func acceleratorParserMapsTokens() async {
        #expect(KSLinuxAcceleratorBackend.toGtkTrigger("Ctrl+Shift+K")
                == "<Control><Shift>k")
        #expect(KSLinuxAcceleratorBackend.toGtkTrigger("CmdOrCtrl+N")
                == "<Control>n")
        #expect(KSLinuxAcceleratorBackend.toGtkTrigger("Alt+F4")
                == "<Alt>F4")
        #expect(KSLinuxAcceleratorBackend.toGtkTrigger("F11")
                == "F11")
        #expect(KSLinuxAcceleratorBackend.toGtkTrigger("garbage+plus+thing")
                == nil)
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
