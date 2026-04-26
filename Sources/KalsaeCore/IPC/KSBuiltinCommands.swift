import Foundation

/// Wires the built-in `__ks.window.*`, `__ks.shell.*`, `__ks.clipboard.*`,
/// `__ks.notification.*`, and `__ks.app.*` commands so the JS-side
/// `__KS_.window.*` namespaces have a Swift counterpart.
///
/// Call this at application startup, after the primary window has been
/// registered with the platform's `KSWindowBackend`. The registrar reads
/// from the supplied platform and resolves the target window via the
/// `mainWindow` handle (used when JS does not specify a `window` field).
///
/// Implementation is split by domain across sibling files:
///   - `KSBuiltinCommands+Window.swift`        — window.*
///   - `KSBuiltinCommands+Shell.swift`         — shell.*
///   - `KSBuiltinCommands+Clipboard.swift`     — clipboard.*
///   - `KSBuiltinCommands+Notification.swift`  — notification.*
///   - `KSBuiltinCommands+App.swift`           — app.*, environment, log
public enum KSBuiltinCommands {
    /// Registers all built-in commands. Calling this more than once
    /// silently overwrites prior handlers.
    public static func register(
        into registry: KSCommandRegistry,
        windows: any KSWindowBackend,
        shell: (any KSShellBackend)?,
        clipboard: (any KSClipboardBackend)?,
        notifications: (any KSNotificationBackend)? = nil,
        mainWindow: @escaping @Sendable () -> KSWindowHandle?,
        quit: @escaping @Sendable () -> Void,
        platformName: String,
        shellScope: KSShellScope = .init(),
        notificationScope: KSNotificationScope = .init()
    ) async {
        let resolver = WindowResolver(windows: windows, mainWindow: mainWindow)

        await registerWindowCommands(into: registry, windows: windows, resolver: resolver)
        if let shell {
            await registerShellCommands(
                into: registry, shell: shell, scope: shellScope)
        }
        if let clipboard {
            await registerClipboardCommands(into: registry, clipboard: clipboard)
        }
        if let notifications {
            await registerNotificationCommands(
                into: registry, notifications: notifications, scope: notificationScope)
        }
        await registerAppCommands(
            into: registry, quit: quit, platformName: platformName)
    }

    // MARK: - Public arg/result types

    public struct Empty: Codable, Sendable {}

    public struct Environment: Codable, Sendable {
        public let os: String
        public let arch: String
        public let platform: String
    }

    // MARK: - Internal arg types
    //
    // 같은 모듈의 extension에서 접근해야 하므로 internal 가시성을 유지한다.
    // 외부 SDK 표면이 아닌 IPC 내부 wire 구조라 추가 노출 위험은 없다.

    struct BoolArg: Codable, Sendable {
        let enabled: Bool
        let window: String?
    }
    struct PositionArg: Codable, Sendable {
        let x: Int
        let y: Int
        let window: String?
    }
    struct SizeArg: Codable, Sendable {
        let width: Int
        let height: Int
        let window: String?
    }
    struct TitleArg: Codable, Sendable {
        let title: String
        let window: String?
    }
    struct ThemeArg: Codable, Sendable {
        let theme: KSWindowTheme
        let window: String?
    }
    struct BackgroundColorArg: Codable, Sendable {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
        let window: String?
    }
    struct URLArg: Codable, Sendable { let url: String }
    struct TextArg: Codable, Sendable { let text: String }
    struct FormatArg: Codable, Sendable { let format: String }
    struct IDArg: Codable, Sendable { let id: String }
    struct LogArg: Codable, Sendable { let level: String; let message: String }

    // MARK: - Generic register helpers

    /// Registers `handler` taking decoded `In` and returning encoded `Out`.
    /// Decode failures surface as `commandDecodeFailed`; non-`KSError`
    /// throws are wrapped as `commandExecutionFailed`.
    static func register<In: Codable & Sendable, Out: Codable & Sendable>(
        _ registry: KSCommandRegistry,
        _ name: String,
        handler: @Sendable @escaping (In) async throws(KSError) -> Out
    ) async {
        await registry.register(name) { data -> Result<Data, KSError> in
            let input: In
            do {
                input = try JSONDecoder().decode(In.self, from: data.isEmpty
                    ? Data("{}".utf8)
                    : data)
            } catch {
                return .failure(KSError(
                    code: .commandDecodeFailed,
                    message: "Failed to decode args for \(name): \(error)"))
            }
            do {
                let out = try await handler(input)
                let encoded = try JSONEncoder().encode(out)
                return .success(encoded)
            } catch let e as KSError {
                return .failure(e)
            } catch {
                return .failure(KSError(
                    code: .commandExecutionFailed,
                    message: "\(error)"))
            }
        }
    }

    /// Same as `register` but for handlers that take no args. Accepts any
    /// JSON shape and ignores it.
    static func register<Out: Codable & Sendable>(
        _ registry: KSCommandRegistry,
        _ name: String,
        handler: @Sendable @escaping (Empty) async throws(KSError) -> Out
    ) async {
        await registry.register(name) { _ -> Result<Data, KSError> in
            do {
                let out = try await handler(Empty())
                let encoded = try JSONEncoder().encode(out)
                return .success(encoded)
            } catch let e as KSError {
                return .failure(e)
            } catch {
                return .failure(KSError(
                    code: .commandExecutionFailed,
                    message: "\(error)"))
            }
        }
    }

    /// Like `register` but advertises that the encoded result is meant
    /// as a query response (semantic alias for readability).
    static func registerQuery<Out: Codable & Sendable>(
        _ registry: KSCommandRegistry,
        _ name: String,
        handler: @Sendable @escaping (Empty) async throws(KSError) -> Out
    ) async {
        await register(registry, name, handler: handler)
    }

    static func registerQuery<In: Codable & Sendable, Out: Codable & Sendable>(
        _ registry: KSCommandRegistry,
        _ name: String,
        handler: @Sendable @escaping (In) async throws(KSError) -> Out
    ) async {
        await register(registry, name, handler: handler)
    }
}

// MARK: - Window resolver

/// Resolves a window label (or absence thereof) to a concrete handle.
/// Used by every `window.*` and any other command that targets a window.
actor WindowResolver {
    let windows: any KSWindowBackend
    let mainWindowProvider: @Sendable () -> KSWindowHandle?

    init(windows: any KSWindowBackend,
         mainWindow: @escaping @Sendable () -> KSWindowHandle?) {
        self.windows = windows
        self.mainWindowProvider = mainWindow
    }

    func resolve(window: String?) async throws(KSError) -> KSWindowHandle {
        if let label = window {
            if let h = await windows.find(label: label) { return h }
            throw KSError(code: .windowCreationFailed,
                          message: "No window registered for label '\(label)'")
        }
        if let h = mainWindowProvider() { return h }
        throw KSError(code: .windowCreationFailed,
                      message: "No primary window registered.")
    }
}

// MARK: - OS/Arch helpers

@inline(__always)
func kalsaeOSName() -> String {
    #if os(Windows)
    return "windows"
    #elseif os(macOS)
    return "macos"
    #elseif os(Linux)
    return "linux"
    #else
    return "unknown"
    #endif
}

@inline(__always)
func kalsaeArchName() -> String {
    #if arch(x86_64)
    return "x86_64"
    #elseif arch(arm64)
    return "arm64"
    #elseif arch(i386)
    return "i386"
    #elseif arch(arm)
    return "arm"
    #else
    return "unknown"
    #endif
}
