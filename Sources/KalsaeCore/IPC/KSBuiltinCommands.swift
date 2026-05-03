/// 내장 `__ks.window.*`, `__ks.shell.*`, `__ks.clipboard.*`,
/// `__ks.notification.*`, `__ks.app.*` 명령을 연결하여 JS 측
/// `__KS_.window.*` 네임스페이스에 Swift 대응부가 있도록 한다.
///
/// 애플리케이션 시작 시, 기본 윈도우가 플랫폼의 `KSWindowBackend`에
/// 등록된 후에 호출한다. 등록자는 제공된 플랫폼에서 읽어와
/// `mainWindow` 핸들(JS가 `window` 필드를 지정하지 않을 때 사용)을
/// 통해 대상 윈도우를 해석한다.
///
/// 구현은 도메인별로 형제 파일에 분할되어 있다:
///   - `KSBuiltinCommands+Window.swift`        — window.*
///   - `KSBuiltinCommands+Shell.swift`         — shell.*
///   - `KSBuiltinCommands+Clipboard.swift`     — clipboard.*
///   - `KSBuiltinCommands+Notification.swift`  — notification.*
///   - `KSBuiltinCommands+App.swift`           — app.*, environment, log
public import Foundation

// MARK: - Window resolver

/// 윈도우 레이블(또는 부재)을 구체적인 핸들로 해석한다.
/// 모든 `window.*` 및 윈도우를 대상으로 하는 다른 명령에서 사용된다.

// MARK: - OS/Arch helpers

/// JS로부터 임의 JSON 값을 왕복하는 데 사용되는 최소 "any JSON" 타입.
/// 내부 — `KSBuiltinCommands.WindowEmitArg.payload` 필드에서만 사용된다.
internal enum KSAnyJSON: Codable, Sendable {
    case null
    case bool(Bool)
    case double(Double)
    case string(String)
    case array([KSAnyJSON])
    case object([String: KSAnyJSON])

    init(from decoder: any Decoder) throws {
        // Codable 프로토콜 — untyped throws (변경 불가)
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([KSAnyJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: KSAnyJSON].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown JSON value")
    }

    func encode(to encoder: any Encoder) throws {
        // Codable 프로토콜 — untyped throws (변경 불가)
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

public enum KSBuiltinCommands {
    /// 모든 내장 명령을 등록한다. 두 번 이상 호출하면
    /// 이전 핸들러를 조용히 덮어쓴다.
    public static func register(
        into registry: KSCommandRegistry,
        windows: any KSWindowBackend,
        shell: (any KSShellBackend)?,
        clipboard: (any KSClipboardBackend)?,
        notifications: (any KSNotificationBackend)? = nil,
        dialogs: (any KSDialogBackend)? = nil,
        mainWindow: @escaping @Sendable () -> KSWindowHandle?,
        quit: @escaping @Sendable () -> Void,
        platformName: String,
        shellScope: KSShellScope = .init(),
        notificationScope: KSNotificationScope = .init(),
        fsScope: KSFSScope = .init(),
        httpScope: KSHTTPScope = .init(),
        autostart: (any KSAutostartBackend)? = nil,
        deepLink: (backend: any KSDeepLinkBackend, config: KSDeepLinkConfig)? = nil,
        appDirectory: URL? = nil
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
        if let dialogs {
            await registerDialogCommands(
                into: registry, dialogs: dialogs, resolver: resolver)
        }
        await registerAppCommands(
            into: registry, quit: quit, platformName: platformName)
        let appDir =
            appDirectory
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        await registerFSCommands(
            into: registry, scope: fsScope, appDirectory: appDir)
        await registerHTTPCommands(
            into: registry, scope: httpScope)
        if let autostart {
            await registerAutostartCommands(into: registry, backend: autostart)
        }
        if let deepLink {
            await registerDeepLinkCommands(
                into: registry, backend: deepLink.backend, config: deepLink.config)
        }
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
    struct ZoomFactorArg: Codable, Sendable {
        let factor: Double
        let window: String?
    }
    struct PrintArg: Codable, Sendable {
        let systemDialog: Bool?
        let window: String?
    }
    struct CaptureArg: Codable, Sendable {
        let format: String?
        let window: String?
    }
    struct WindowEmitArg: Codable, Sendable {
        let event: String
        let payload: KSAnyJSON
        let target: String?
    }
    struct WindowInfo: Codable, Sendable {
        let label: String
    }
    struct LabelResult: Codable, Sendable {
        let label: String
    }
    struct URLArg: Codable, Sendable { let url: String }
    struct TextArg: Codable, Sendable { let text: String }
    struct FormatArg: Codable, Sendable { let format: String }
    struct IDArg: Codable, Sendable { let id: String }
    struct LogArg: Codable, Sendable {
        let level: String
        let message: String
    }

    // MARK: - Generic register helpers

    /// 디코딩된 `In`을 받아 인코딩된 `Out`을 반환하는 `handler`를 등록한다.
    /// 디코딩 실패는 `commandDecodeFailed`로 표시되고, `KSError`가 아닌
    /// throw는 `commandExecutionFailed`로 감싸진다.
    static func register<In: Codable & Sendable, Out: Codable & Sendable>(
        _ registry: KSCommandRegistry,
        _ name: String,
        handler: @Sendable @escaping (In) async throws(KSError) -> Out
    ) async {
        await registry.register(name) { data -> Result<Data, KSError> in
            let input: In
            do {
                input = try JSONDecoder().decode(
                    In.self,
                    from: data.isEmpty
                        ? Data("{}".utf8)
                        : data)
            } catch {
                return .failure(
                    KSError(
                        code: .commandDecodeFailed,
                        message: "Failed to decode args for \(name): \(error)"))
            }
            do {
                let out = try await handler(input)
                let encoded = try JSONEncoder().encode(out)
                return .success(encoded)
            } catch let e as KSError {
                // 혼합 throw 지점 (JSONEncoder + handler(KSError)) — AGENTS §4 참조
                return .failure(e)
            } catch {
                return .failure(
                    KSError(
                        code: .commandExecutionFailed,
                        message: "\(error)"))
            }
        }
    }

    /// `register`와 동일하지만 인자를 받지 않는 핸들러용. 모든 JSON
    /// 형태를 수용하고 무시한다.
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
                // 혼합 throw 지점 (JSONEncoder + handler(KSError)) — AGENTS §4 참조
                return .failure(e)
            } catch {
                return .failure(
                    KSError(
                        code: .commandExecutionFailed,
                        message: "\(error)"))
            }
        }
    }

    /// `register`와 유사하지만 인코딩된 결과가 쿼리 응답으로
    /// 의도되었음을 알린다 (가독성을 위한 의미론적 별칭).
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
actor WindowResolver {
    let windows: any KSWindowBackend
    let mainWindowProvider: @Sendable () -> KSWindowHandle?

    init(
        windows: any KSWindowBackend,
        mainWindow: @escaping @Sendable () -> KSWindowHandle?
    ) {
        self.windows = windows
        self.mainWindowProvider = mainWindow
    }

    func resolve(window: String?) async throws(KSError) -> KSWindowHandle {
        if let label = window {
            if let h = await windows.find(label: label) { return h }
            throw KSError(
                code: .windowCreationFailed,
                message: "No window registered for label '\(label)'")
        }
        // `window` 인자 없이 호출된 경우 IPC 프레임이 전달된 창 레이블
        // (TaskLocal)을 먼저 시도한다. 이렇게 하면 두 번째 창에서
        // `minimize()`를 호출할 때 main 창이 아닌 호출자 창이 최소화된다.
        if let label = KSInvocationContext.windowLabel,
            let h = await windows.find(label: label)
        {
            return h
        }
        if let h = mainWindowProvider() { return h }
        throw KSError(
            code: .windowCreationFailed,
            message: "No primary window registered.")
    }
}
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
