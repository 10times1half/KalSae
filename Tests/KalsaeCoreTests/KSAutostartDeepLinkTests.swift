import Testing
import Foundation
@testable import KalsaeCore

@Suite("KSAutostartConfig + KSDeepLinkConfig")
struct KSAutostartConfigTests {
    @Test("Autostart Codable defaults")
    func autostartDefaults() throws {
        let cfg = try JSONDecoder().decode(KSAutostartConfig.self, from: Data("{}".utf8))
        #expect(cfg.args.isEmpty)
    }

    @Test("Autostart Codable round-trip")
    func autostartRoundTrip() throws {
        let cfg = KSAutostartConfig(args: ["--launched-by-os", "--minimized"])
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(KSAutostartConfig.self, from: data)
        #expect(decoded == cfg)
    }

    @Test("DeepLink Codable defaults")
    func deepLinkDefaults() throws {
        let cfg = try JSONDecoder().decode(KSDeepLinkConfig.self, from: Data("{}".utf8))
        #expect(cfg.schemes.isEmpty)
        #expect(!cfg.autoRegisterOnLaunch)
    }

    @Test("DeepLink Codable round-trip")
    func deepLinkRoundTrip() throws {
        let cfg = KSDeepLinkConfig(
            schemes: ["myapp", "myapp-dev"],
            autoRegisterOnLaunch: true)
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(KSDeepLinkConfig.self, from: data)
        #expect(decoded == cfg)
    }
}

@Suite("KSWindowStateStore")
struct KSWindowStateStoreTests {
    private func makeTempStore() -> KSWindowStateStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kalsae-tests-\(UUID().uuidString).json")
        return KSWindowStateStore(url: url)
    }

    @Test("load returns nil when the file does not exist")
    func loadMissing() {
        let store = makeTempStore()
        #expect(store.load(label: "main") == nil)
    }

    @Test("save then load round-trips state")
    func saveLoad() {
        let store = makeTempStore()
        defer { try? FileManager.default.removeItem(at: store.url) }
        let s = KSPersistedWindowState(
            x: 100, y: 200, width: 1024, height: 768,
            maximized: true, fullscreen: false)
        #expect(store.save(label: "main", state: s))
        let loaded = store.load(label: "main")
        #expect(loaded == s)
    }

    @Test("save preserves entries for other labels")
    func multiLabel() {
        let store = makeTempStore()
        defer { try? FileManager.default.removeItem(at: store.url) }
        let a = KSPersistedWindowState(x: 1, y: 2, width: 3, height: 4)
        let b = KSPersistedWindowState(x: 10, y: 20, width: 30, height: 40)
        #expect(store.save(label: "a", state: a))
        #expect(store.save(label: "b", state: b))
        #expect(store.load(label: "a") == a)
        #expect(store.load(label: "b") == b)
    }

    @Test("load returns nil for an unknown label inside a valid file")
    func unknownLabel() {
        let store = makeTempStore()
        defer { try? FileManager.default.removeItem(at: store.url) }
        let s = KSPersistedWindowState()
        #expect(store.save(label: "main", state: s))
        #expect(store.load(label: "missing") == nil)
    }
}
