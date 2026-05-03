import Foundation
import Testing

@testable import KalsaeCore

// MARK: - Minimal stub backend

/// `all` / `find` 만 필요한 WindowResolver 테스트용 최소 스텁.
/// 프로토콜 기본 구현이 없는 메서드만 명시적으로 구현한다.
actor StubWindowBackend: KSWindowBackend {
    private var handles: [KSWindowHandle] = []

    func seed(_ h: KSWindowHandle) { handles.append(h) }

    // KSWindowLifecycle (no default)
    func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
        throw KSError(code: .unsupportedPlatform, message: "stub")
    }
    func close(_ handle: KSWindowHandle) async throws(KSError) {}
    func show(_ handle: KSWindowHandle) async throws(KSError) {}
    func hide(_ handle: KSWindowHandle) async throws(KSError) {}
    func focus(_ handle: KSWindowHandle) async throws(KSError) {}
    func webView(for handle: KSWindowHandle) async throws(KSError) -> any KSWebViewBackend {
        throw KSError(code: .unsupportedPlatform, message: "stub")
    }
    func all() async -> [KSWindowHandle] { handles }
    func find(label: String) async -> KSWindowHandle? {
        handles.first { $0.label == label }
    }

    // KSWindowGeometry (no default)
    func setSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {}

    // KSWindowState (no default)
    func setTitle(_ handle: KSWindowHandle, title: String) async throws(KSError) {}
}

private func makeHandle(_ label: String) -> KSWindowHandle {
    KSWindowHandle(label: label, rawValue: UInt64(label.hashValue & 0xFFFF_FFFF))
}

// MARK: - Tests

@Suite("WindowResolver")
struct KSWindowResolverTests {

    // ── 1. explicit label ──────────────────────────────────────────

    @Test("explicit label resolves matching handle")
    func explicitLabel() async throws {
        let backend = StubWindowBackend()
        let hA = makeHandle("win-a")
        let hB = makeHandle("win-b")
        await backend.seed(hA)
        await backend.seed(hB)

        let resolver = WindowResolver(windows: backend, mainWindow: { nil })
        let result = try await resolver.resolve(window: "win-b")
        #expect(result.label == "win-b")
    }

    @Test("explicit label for unknown window throws windowCreationFailed")
    func explicitLabelUnknown() async {
        let backend = StubWindowBackend()
        let resolver = WindowResolver(windows: backend, mainWindow: { nil })
        await #expect(throws: KSError.self) {
            _ = try await resolver.resolve(window: "ghost")
        }
    }

    // ── 2. TaskLocal fallback ──────────────────────────────────────

    @Test("nil window arg falls back to KSInvocationContext.windowLabel")
    func taskLocalFallback() async throws {
        let backend = StubWindowBackend()
        let hA = makeHandle("win-a")
        let hB = makeHandle("win-b")
        await backend.seed(hA)
        await backend.seed(hB)

        // mainWindow provider returns win-a, but TaskLocal says win-b.
        let resolver = WindowResolver(windows: backend, mainWindow: { hA })

        let result = try await KSInvocationContext.$windowLabel.withValue("win-b") {
            try await resolver.resolve(window: nil)
        }
        #expect(result.label == "win-b")
    }

    @Test("TaskLocal label for unregistered window falls through to mainWindow")
    func taskLocalFallthrough() async throws {
        let backend = StubWindowBackend()
        let hA = makeHandle("win-a")
        await backend.seed(hA)

        // TaskLocal is set to an unknown label — falls through to mainWindow.
        let resolver = WindowResolver(windows: backend, mainWindow: { hA })

        let result = try await KSInvocationContext.$windowLabel.withValue("unknown") {
            try await resolver.resolve(window: nil)
        }
        #expect(result.label == "win-a")
    }

    // ── 3. mainWindow fallback ─────────────────────────────────────

    @Test("nil window arg with no TaskLocal resolves mainWindow")
    func mainWindowFallback() async throws {
        let backend = StubWindowBackend()
        let hA = makeHandle("main")
        await backend.seed(hA)

        let resolver = WindowResolver(windows: backend, mainWindow: { hA })
        let result = try await resolver.resolve(window: nil)
        #expect(result.label == "main")
    }

    @Test("nil window arg with no TaskLocal and no mainWindow throws")
    func noContextThrows() async {
        let backend = StubWindowBackend()
        let resolver = WindowResolver(windows: backend, mainWindow: { nil })
        await #expect(throws: KSError.self) {
            _ = try await resolver.resolve(window: nil)
        }
    }

    // ── 4. explicit label overrides TaskLocal ──────────────────────

    @Test("explicit label takes precedence over TaskLocal")
    func explicitOverridesTaskLocal() async throws {
        let backend = StubWindowBackend()
        let hA = makeHandle("win-a")
        let hB = makeHandle("win-b")
        await backend.seed(hA)
        await backend.seed(hB)

        let resolver = WindowResolver(windows: backend, mainWindow: { hA })

        // TaskLocal says win-a, explicit arg says win-b.
        let result = try await KSInvocationContext.$windowLabel.withValue("win-a") {
            try await resolver.resolve(window: "win-b")
        }
        #expect(result.label == "win-b")
    }
}
