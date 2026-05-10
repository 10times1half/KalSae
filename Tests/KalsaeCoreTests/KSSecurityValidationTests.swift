import Foundation
import Testing

@testable import KalsaeCore

// MARK: - Stub backends

/// `__ks.shell.*` 검증 테스트용 최소 스텁. 모든 호출을 기록하여 검증이
/// 실패했는지(=PAL 호출이 일어나지 않았는지) 확인한다.
actor StubShellBackend: KSShellBackend {
    private(set) var openExternalCalls: [URL] = []
    private(set) var showItemCalls: [URL] = []
    private(set) var moveToTrashCalls: [URL] = []

    func openExternal(_ url: URL) async throws(KSError) {
        openExternalCalls.append(url)
    }
    func showItemInFolder(_ url: URL) async throws(KSError) {
        showItemCalls.append(url)
    }
    func moveToTrash(_ url: URL) async throws(KSError) {
        moveToTrashCalls.append(url)
    }
}

actor StubNotificationBackend: KSNotificationBackend {
    private(set) var posted: [KSNotification] = []
    func requestPermission() async -> Bool { true }
    func post(_ notification: KSNotification) async throws(KSError) {
        posted.append(notification)
    }
    func cancel(id: String) async {}
}

actor StubDialogBackend: KSDialogBackend {
    private(set) var lastOpenDir: URL?
    private(set) var lastSaveDir: URL?
    private(set) var lastFolderDir: URL?

    func openFile(options: KSOpenFileOptions, parent: KSWindowHandle?) async throws(KSError) -> [URL] {
        lastOpenDir = options.defaultDirectory
        return []
    }
    func saveFile(options: KSSaveFileOptions, parent: KSWindowHandle?) async throws(KSError) -> URL? {
        lastSaveDir = options.defaultDirectory
        return nil
    }
    func selectFolder(options: KSSelectFolderOptions, parent: KSWindowHandle?) async throws(KSError) -> URL? {
        lastFolderDir = options.defaultDirectory
        return nil
    }
    func message(_ options: KSMessageOptions, parent: KSWindowHandle?) async throws(KSError) -> KSMessageResult {
        .ok
    }
}

// MARK: - Helpers

private func makeFsCtx() -> KSFSScope.ExpansionContext {
    KSFSScope.ExpansionContext(
        app: "/app", home: "/home/user", docs: "/home/user/Documents", temp: "/tmp")
}

private func dispatchExpect<Out: Decodable>(
    _ registry: KSCommandRegistry,
    _ name: String,
    args: String,
    as: Out.Type
) async throws -> Out {
    let result = await registry.dispatch(name: name, args: Data(args.utf8))
    switch result {
    case .success(let data):
        return try JSONDecoder().decode(Out.self, from: data)
    case .failure(let error):
        throw error
    }
}

private func dispatchExpectError(
    _ registry: KSCommandRegistry,
    _ name: String,
    args: String
) async -> KSError? {
    let result = await registry.dispatch(name: name, args: Data(args.utf8))
    if case .failure(let error) = result {
        return error
    }
    return nil
}

private struct EmptyDTO: Decodable {}

// MARK: - Shell path validation (RFC-002 §2.1)

@Suite("RFC-002 §2.1 — shell path validation")
struct KSShellPathValidationTests {

    private func makeRegistry(
        scope: KSShellScope
    ) async -> (KSCommandRegistry, StubShellBackend) {
        let registry = KSCommandRegistry()
        let backend = StubShellBackend()
        await KSBuiltinCommands.registerShellCommands(
            into: registry, shell: backend, scope: scope, fsCtx: makeFsCtx())
        return (registry, backend)
    }

    @Test("showItemInFolder denies unallowed path (default empty fsScope)")
    func showItemDeniedByDefault() async throws {
        let (registry, backend) = await makeRegistry(scope: KSShellScope())
        let err = await dispatchExpectError(
            registry, "__ks.shell.showItemInFolder",
            args: #"{"url":"/etc/passwd"}"#)
        #expect(err?.code == .fsScopeDenied)
        let calls = await backend.showItemCalls
        #expect(calls.isEmpty)
    }

    @Test("showItemInFolder allows path within fsScope")
    func showItemAllowedByFsScope() async throws {
        let scope = KSShellScope(
            fsScope: KSFSScope(allow: ["$HOME/Documents/**"]))
        let (registry, backend) = await makeRegistry(scope: scope)
        _ = try await dispatchExpect(
            registry, "__ks.shell.showItemInFolder",
            args: #"{"url":"/home/user/Documents/report.pdf"}"#,
            as: EmptyDTO.self)
        let calls = await backend.showItemCalls
        #expect(calls.count == 1)
        // RFC-002 — 검증한 expanded URL이 PAL에 전달되어야 한다 (TOCTOU 방지).
        #expect(calls.first?.path.hasSuffix("/home/user/Documents/report.pdf") == true)
    }

    @Test("moveToTrash denies path outside fsScope.allow")
    func moveToTrashDeniedOutsideScope() async throws {
        let scope = KSShellScope(fsScope: KSFSScope(allow: ["$HOME/Trash/**"]))
        let (registry, backend) = await makeRegistry(scope: scope)
        let err = await dispatchExpectError(
            registry, "__ks.shell.moveToTrash",
            args: #"{"url":"/home/user/Documents/secrets.txt"}"#)
        #expect(err?.code == .fsScopeDenied)
        let calls = await backend.moveToTrashCalls
        #expect(calls.isEmpty)
    }

    @Test("moveToTrash boolean disabled flag still wins")
    func moveToTrashBooleanDisabled() async throws {
        let scope = KSShellScope(
            moveToTrash: false,
            fsScope: KSFSScope(allow: ["$HOME/**"]))
        let (registry, _) = await makeRegistry(scope: scope)
        let err = await dispatchExpectError(
            registry, "__ks.shell.moveToTrash",
            args: #"{"url":"/home/user/Documents/x.txt"}"#)
        #expect(err?.code == .commandNotAllowed)
    }
}

// MARK: - Notification iconPath validation (RFC-002 §2.2-bis)

@Suite("RFC-002 §2.2-bis — notification iconPath validation")
struct KSNotificationIconPathValidationTests {

    private func makeRegistry(
        fsScope: KSFSScope
    ) async -> (KSCommandRegistry, StubNotificationBackend) {
        let registry = KSCommandRegistry()
        let backend = StubNotificationBackend()
        await KSBuiltinCommands.registerNotificationCommands(
            into: registry,
            notifications: backend,
            scope: KSNotificationScope(),
            fsScope: fsScope,
            fsCtx: makeFsCtx())
        return (registry, backend)
    }

    @Test("post without iconPath bypasses fsScope check")
    func postWithoutIconPath() async throws {
        let (registry, backend) = await makeRegistry(fsScope: KSFSScope())
        _ = try await dispatchExpect(
            registry, "__ks.notification.post",
            args: #"{"id":"n1","title":"hello"}"#,
            as: EmptyDTO.self)
        let posted = await backend.posted
        #expect(posted.count == 1)
        #expect(posted.first?.iconPath == nil)
    }

    @Test("post with iconPath outside fsScope is rejected")
    func postWithDisallowedIconPath() async throws {
        let (registry, backend) = await makeRegistry(fsScope: KSFSScope())
        let err = await dispatchExpectError(
            registry, "__ks.notification.post",
            args: #"{"id":"n1","title":"x","iconPath":"/etc/passwd"}"#)
        #expect(err?.code == .fsScopeDenied)
        let posted = await backend.posted
        #expect(posted.isEmpty)
    }

    @Test("post with iconPath inside fsScope passes through (validated path)")
    func postWithAllowedIconPath() async throws {
        let scope = KSFSScope(allow: ["$HOME/Pictures/**"])
        let (registry, backend) = await makeRegistry(fsScope: scope)
        _ = try await dispatchExpect(
            registry, "__ks.notification.post",
            args: #"{"id":"n1","title":"x","iconPath":"/home/user/Pictures/icon.png"}"#,
            as: EmptyDTO.self)
        let posted = await backend.posted
        #expect(posted.count == 1)
        // RFC-002 — 검증한 expanded 경로가 PAL에 전달되어야 한다.
        #expect(posted.first?.iconPath?.hasSuffix("/home/user/Pictures/icon.png") == true)
    }
}

// MARK: - Dialog defaultDirectory validation (RFC-002 §2.5)

@Suite("RFC-002 §2.5 — dialog defaultDirectory validation")
struct KSDialogDefaultDirectoryValidationTests {

    private func makeRegistry(
        fsScope: KSFSScope
    ) async -> (KSCommandRegistry, StubDialogBackend) {
        let registry = KSCommandRegistry()
        let backend = StubDialogBackend()
        let windowsBackend = StubWindowBackend()
        let resolver = WindowResolver(windows: windowsBackend, mainWindow: { nil })
        await KSBuiltinCommands.registerDialogCommands(
            into: registry,
            dialogs: backend,
            resolver: resolver,
            fsScope: fsScope,
            fsCtx: makeFsCtx())
        return (registry, backend)
    }

    @Test("openFile rejects defaultDirectory outside fsScope")
    func openFileRejected() async throws {
        let (registry, _) = await makeRegistry(fsScope: KSFSScope())
        let err = await dispatchExpectError(
            registry, "__ks.dialog.openFile",
            args: #"{"defaultDirectory":"/etc"}"#)
        #expect(err?.code == .fsScopeDenied)
    }

    @Test("openFile accepts defaultDirectory inside fsScope")
    func openFileAccepted() async throws {
        // `$HOME/**` 글롭은 정규식 `^/home/user/.*$`로 변환되어 디렉터리 경로도 매치한다.
        let scope = KSFSScope(allow: ["$HOME/**"])
        let (registry, backend) = await makeRegistry(fsScope: scope)
        _ = try await dispatchExpect(
            registry, "__ks.dialog.openFile",
            args: #"{"defaultDirectory":"/home/user/Documents"}"#,
            as: KSBuiltinCommands.OpenFileResult.self)
        let dir = await backend.lastOpenDir
        #expect(dir?.path.hasSuffix("/home/user/Documents") == true)
    }

    @Test("saveFile rejects defaultDirectory outside fsScope")
    func saveFileRejected() async throws {
        let (registry, _) = await makeRegistry(fsScope: KSFSScope())
        let err = await dispatchExpectError(
            registry, "__ks.dialog.saveFile",
            args: #"{"defaultDirectory":"/etc"}"#)
        #expect(err?.code == .fsScopeDenied)
    }

    @Test("selectFolder rejects defaultDirectory outside fsScope")
    func selectFolderRejected() async throws {
        let (registry, _) = await makeRegistry(fsScope: KSFSScope())
        let err = await dispatchExpectError(
            registry, "__ks.dialog.selectFolder",
            args: #"{"defaultDirectory":"/etc"}"#)
        #expect(err?.code == .fsScopeDenied)
    }

    @Test("openFile with no defaultDirectory bypasses fsScope")
    func openFileNoDir() async throws {
        let (registry, backend) = await makeRegistry(fsScope: KSFSScope())
        _ = try await dispatchExpect(
            registry, "__ks.dialog.openFile",
            args: #"{}"#,
            as: KSBuiltinCommands.OpenFileResult.self)
        let dir = await backend.lastOpenDir
        #expect(dir == nil)
    }
}

// MARK: - Window setSize / setPosition / setOverlayIcon / create (RFC-002 §2.2, §2.4, §2.6)

@Suite("RFC-002 §2.2/§2.4/§2.6 — window handler validation")
struct KSWindowHandlerValidationTests {

    private func makeRegistry(
        fsScope: KSFSScope = KSFSScope(),
        navigationScope: KSNavigationScope = KSNavigationScope()
    ) async -> (KSCommandRegistry, StubWindowBackend) {
        let registry = KSCommandRegistry()
        let backend = StubWindowBackend()
        await backend.seed(KSWindowHandle(label: "main", rawValue: 1))
        let resolver = WindowResolver(windows: backend, mainWindow: { nil })
        await KSBuiltinCommands.registerWindowCommands(
            into: registry,
            windows: backend,
            resolver: resolver,
            fsScope: fsScope,
            fsCtx: makeFsCtx(),
            navigationScope: navigationScope)
        return (registry, backend)
    }

    // ── setSize (§2.6) ────────────────────────────

    @Test("setSize rejects zero or negative dimensions")
    func setSizeRejectsNonPositive() async throws {
        let (registry, _) = await makeRegistry()
        let e1 = await dispatchExpectError(
            registry, "__ks.window.setSize",
            args: #"{"width":0,"height":600,"window":"main"}"#)
        #expect(e1?.code == .invalidArgument)
        let e2 = await dispatchExpectError(
            registry, "__ks.window.setSize",
            args: #"{"width":-1,"height":600,"window":"main"}"#)
        #expect(e2?.code == .invalidArgument)
    }

    @Test("setSize rejects dimensions exceeding 65535")
    func setSizeRejectsHugeValues() async throws {
        let (registry, _) = await makeRegistry()
        let err = await dispatchExpectError(
            registry, "__ks.window.setSize",
            args: #"{"width":99999999,"height":600,"window":"main"}"#)
        #expect(err?.code == .invalidArgument)
    }

    @Test("setSize accepts reasonable dimensions")
    func setSizeAcceptsNormal() async throws {
        let (registry, _) = await makeRegistry()
        _ = try await dispatchExpect(
            registry, "__ks.window.setSize",
            args: #"{"width":1280,"height":720,"window":"main"}"#,
            as: EmptyDTO.self)
    }

    // ── setPosition (§2.6) ────────────────────────
    //  §2.6 결정: setPosition 경계 검사는 의도적으로 없다 (멀티모니터
    //  호환성). 스텁이 setPosition을 미구현하므로 PAL 호출 테스트는 퍼옦터
    //  검사만 다루는 setSize 테스트에 포함한다.

    // ── window.create URL (§2.4) ──────────────────

    @Test("window.create with URL outside navigationScope is rejected before backend.create")
    func createRejectsDisallowedURL() async throws {
        let nav = KSNavigationScope(allow: ["https://app.example.com/**"])
        let (registry, _) = await makeRegistry(navigationScope: nav)
        let err = await dispatchExpectError(
            registry, "__ks.window.create",
            args:
                #"{"label":"phish","title":"x","url":"https://evil.com/login","width":100,"height":100,"resizable":true,"decorations":true,"transparent":false,"fullscreen":false,"visible":true,"center":true,"alwaysOnTop":false,"hideOnClose":false,"disableWindowIcon":false,"contentProtection":false,"persistState":false}"#
        )
        // 검증이 backend.create() 이전에 일어나므로 commandNotAllowed가 반환되어야 한다.
        // (StubWindowBackend.create()는 unsupportedPlatform을 던지므로, 검증을 통과하면
        // 다른 에러 코드가 나온다 — 이 차이로 검증 시점을 구분한다.)
        #expect(err?.code == .commandNotAllowed)
    }

    @Test("window.create permits URLs allowed by navigationScope")
    func createAllowsPermittedURL() async throws {
        let nav = KSNavigationScope(allow: ["https://app.example.com/**"])
        let (registry, _) = await makeRegistry(navigationScope: nav)
        // StubWindowBackend.create() throws unsupportedPlatform — URL 검증은 통과해야 함.
        let err = await dispatchExpectError(
            registry, "__ks.window.create",
            args:
                #"{"label":"ok","title":"x","url":"https://app.example.com/index","width":100,"height":100,"resizable":true,"decorations":true,"transparent":false,"fullscreen":false,"visible":true,"center":true,"alwaysOnTop":false,"hideOnClose":false,"disableWindowIcon":false,"contentProtection":false,"persistState":false}"#
        )
        // 검증 자체는 통과 → backend.create()가 unsupportedPlatform을 던진다 (commandNotAllowed가 아니면 OK).
        #expect(err?.code != .commandNotAllowed)
    }

    @Test("window.create with empty navigation allow list permits any URL (legacy)")
    func createAllowsAnyURLByDefault() async throws {
        let (registry, _) = await makeRegistry(navigationScope: KSNavigationScope())
        // 빈 allow 목록은 "제한 없음"을 뜻한다 — 검증은 통과한다.
        let err = await dispatchExpectError(
            registry, "__ks.window.create",
            args:
                #"{"label":"any","title":"x","url":"file:///etc/passwd","width":100,"height":100,"resizable":true,"decorations":true,"transparent":false,"fullscreen":false,"visible":true,"center":true,"alwaysOnTop":false,"hideOnClose":false,"disableWindowIcon":false,"contentProtection":false,"persistState":false}"#
        )
        // 빈 navigation scope에서는 검증 통과 → backend.create()가 unsupportedPlatform.
        #expect(err?.code != .commandNotAllowed)
    }

    // ── setOverlayIcon (§2.2) ─────────────────────

    @Test("setOverlayIcon rejects iconPath outside fsScope")
    func overlayIconRejected() async throws {
        let (registry, _) = await makeRegistry(fsScope: KSFSScope())
        let err = await dispatchExpectError(
            registry, "__ks.window.setOverlayIcon",
            args: #"{"iconPath":"/etc/passwd","window":"main"}"#)
        #expect(err?.code == .fsScopeDenied)
    }

    @Test("setOverlayIcon with nil iconPath bypasses fsScope check")
    func overlayIconNilPath() async throws {
        let (registry, _) = await makeRegistry(fsScope: KSFSScope())
        _ = try await dispatchExpect(
            registry, "__ks.window.setOverlayIcon",
            args: #"{"window":"main"}"#,
            as: EmptyDTO.self)
    }
}
