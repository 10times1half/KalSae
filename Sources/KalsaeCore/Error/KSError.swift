import Foundation
internal import Logging

/// Unified, Codable error type used throughout Kalsae.
///
/// Every `@KSCommand` function is declared as `async throws(KSError)` so that
/// errors can be serialized verbatim to the JS frontend as
/// `{ code, message, data? }`.
public struct KSError: Error, Codable, Sendable, Equatable, CustomStringConvertible {
    /// Stable, machine-readable identifier. Frontend code may switch on this.
    public let code: Code
    /// Human-readable description, safe to surface to end users in dev builds.
    public let message: String
    /// Optional structured payload (e.g. path, underlying OS error code).
    public let data: Payload?
    /// Optional source-location capture. Populated by convenience
    /// constructors that take `#file/#line/#function`. Excluded from
    /// JSON wire output so it never leaks into release telemetry.
    public let sourceLocation: SourceLocation?

    public init(code: Code,
                message: String,
                data: Payload? = nil,
                sourceLocation: SourceLocation? = nil) {
        self.code = code
        self.message = message
        self.data = data
        self.sourceLocation = sourceLocation
    }

    public var description: String {
        if let loc = sourceLocation {
            return "KSError(\(code.rawValue)) at \(loc): \(message)"
        }
        return "KSError(\(code.rawValue)): \(message)"
    }

    // MARK: - Wire codable

    private enum CodingKeys: String, CodingKey {
        case code, message, data
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try c.decode(Code.self, forKey: .code)
        self.message = try c.decode(String.self, forKey: .message)
        self.data = try c.decodeIfPresent(Payload.self, forKey: .data)
        self.sourceLocation = nil
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(message, forKey: .message)
        try c.encodeIfPresent(data, forKey: .data)
        // sourceLocation은 재현성 일관성과 안전을 위해 압축하지 않는다.
    }

    // MARK: - Source location

    /// Capture of where a `KSError` was constructed. Useful for logs and
    /// debugging; never serialized over the wire.
    public struct SourceLocation: Sendable, Equatable, CustomStringConvertible {
        public let file: String
        public let line: Int
        public let function: String

        public init(file: String, line: Int, function: String) {
            // 파일 경로의 의미있는 마지막 두 단마만 남겨 로그를 간결히 유지한다.
            let parts = file.split(separator: "/", omittingEmptySubsequences: true)
            self.file = parts.suffix(2).joined(separator: "/")
            self.line = line
            self.function = function
        }

        public var description: String { "\(file):\(line) (\(function))" }
    }

    // MARK: - Code

    public enum Code: String, Codable, Sendable, CaseIterable {
        // 구성 / 부트스트랩
        case configNotFound
        case configInvalid
        case unsupportedPlatform

        // 플랫폼 백엔드
        case platformInitFailed
        case windowCreationFailed
        case webviewInitFailed
        case schemeHandlerFailed

        // 네이티브 모듈 프로세스 간 통신
        case commandNotFound
        case commandNotAllowed
        case commandDecodeFailed
        case commandEncodeFailed
        case commandExecutionFailed

        // 파일 시스템 / 보안
        case fsScopeDenied
        case ioFailed

        // 클립보드
        case clipboardDecodeFailed

        // 외부 프로세스 / 셰트
        case shellInvocationFailed

        // 일반
        case cancelled
        case invalidArgument
        case `internal`
    }

    // MARK: - Payload

    /// A small, JSON-friendly value used for `data`.
    public enum Payload: Codable, Sendable, Equatable {
        case string(String)
        case int(Int)
        case dict([String: Payload])
        case array([Payload])
        case null

        // 태그 붙은 열거이 아닌 일반 JSON 값으로 직렬화되도록
        // 커스텀 코딩을 제공한다.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() {
                self = .null
            } else if let s = try? c.decode(String.self) {
                self = .string(s)
            } else if let i = try? c.decode(Int.self) {
                self = .int(i)
            } else if let a = try? c.decode([Payload].self) {
                self = .array(a)
            } else if let d = try? c.decode([String: Payload].self) {
                self = .dict(d)
            } else {
                // 디코딩 실패의 원인을 추적할 수 있도록 진단 로그를 남긴다.
                Logger(label: "kalsae.error.payload").debug(
                    "unsupported KSError.Payload value (not null/string/int/array/dict)")
                throw DecodingError.dataCorruptedError(
                    in: c,
                    debugDescription: "Unsupported KSError.Payload value")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let s): try c.encode(s)
            case .int(let i): try c.encode(i)
            case .array(let a): try c.encode(a)
            case .dict(let d): try c.encode(d)
            case .null: try c.encodeNil()
            }
        }
    }
}

// MARK: - Convenience constructors

extension KSError {
    public static func configNotFound(_ path: String) -> KSError {
        KSError(code: .configNotFound,
                message: "Kalsae.json not found at \(path)",
                data: .string(path))
    }

    public static func configInvalid(_ reason: String) -> KSError {
        KSError(code: .configInvalid,
                message: "Invalid Kalsae.json: \(reason)")
    }

    public static func unsupportedPlatform(_ detail: String = "") -> KSError {
        KSError(code: .unsupportedPlatform,
                message: detail.isEmpty
                    ? "This platform is not supported."
                    : "Unsupported platform: \(detail)")
    }

    public static func commandNotAllowed(_ name: String) -> KSError {
        KSError(code: .commandNotAllowed,
                message: "Command '\(name)' is not in the allowlist.",
                data: .string(name))
    }

    public static func commandNotFound(_ name: String) -> KSError {
        KSError(code: .commandNotFound,
                message: "Command '\(name)' is not registered.",
                data: .string(name))
    }

    public static func `internal`(_ reason: String,
                                  file: String = #fileID,
                                  line: Int = #line,
                                  function: String = #function) -> KSError {
        KSError(code: .internal, message: reason,
                sourceLocation: SourceLocation(
                    file: file, line: line, function: function))
    }

    /// Source-located convenience for clipboard decode failures.
    public static func clipboardDecodeFailed(_ reason: String,
                                             file: String = #fileID,
                                             line: Int = #line,
                                             function: String = #function) -> KSError {
        KSError(code: .clipboardDecodeFailed,
                message: "Clipboard decode failed: \(reason)",
                sourceLocation: SourceLocation(
                    file: file, line: line, function: function))
    }

    /// Source-located convenience for shell-out failures (CLI Packager etc.).
    public static func shellInvocationFailed(
        command: String,
        exitCode: Int32,
        stderr: String? = nil,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) -> KSError {
        var dict: [String: Payload] = [
            "command": .string(command),
            "exitCode": .int(Int(exitCode)),
        ]
        if let stderr { dict["stderr"] = .string(stderr) }
        return KSError(
            code: .shellInvocationFailed,
            message: "'\(command)' exited with code \(exitCode)",
            data: .dict(dict),
            sourceLocation: SourceLocation(
                file: file, line: line, function: function))
    }
}
