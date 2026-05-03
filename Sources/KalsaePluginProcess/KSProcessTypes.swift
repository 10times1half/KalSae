import Foundation
public import KalsaeCore

// MARK: - 공개 타입

/// 자식 프로세스 실행 옵션.
public struct KSSpawnOptions: Codable, Sendable {
    /// 실행 파일 전체 경로 (예: `/usr/bin/echo`, `C:\Windows\System32\cmd.exe`).
    public var program: String
    /// 명령줄 인수 (기본값: `[]`).
    public var args: [String]
    /// 작업 디렉터리 경로. `nil`이면 현재 프로세스의 작업 디렉터리를 상속한다.
    public var cwd: String?
    /// 환경 변수 딕셔너리. `nil`이면 부모 프로세스 환경을 상속한다.
    public var env: [String: String]?
    /// `true`이면 stdin 파이프를 열어 `kalsae.process.write()` 가능하게 한다.
    public var pipeStdin: Bool

    public init(
        program: String,
        args: [String] = [],
        cwd: String? = nil,
        env: [String: String]? = nil,
        pipeStdin: Bool = false
    ) {
        self.program = program
        self.args = args
        self.cwd = cwd
        self.env = env
        self.pipeStdin = pipeStdin
    }
}

/// 자식 프로세스 핸들 — 후속 명령(`write`, `kill`, `wait`)에서 프로세스를 식별한다.
public struct KSChildHandle: Codable, Sendable, Hashable {
    /// UUID 문자열 형식의 프로세스 ID.
    public var id: String

    public init(id: String) { self.id = id }
}

/// 프로세스 종료 정보.
public struct KSExitInfo: Codable, Sendable {
    /// 정상 종료 코드. 시그널로 종료된 경우 `nil`.
    public var code: Int32?
    /// 종료 시그널 번호 (Unix 전용). 정상 종료된 경우 `nil`.
    public var signal: Int32?

    public init(code: Int32?, signal: Int32?) {
        self.code = code
        self.signal = signal
    }
}

// MARK: - 내부 이벤트 페이로드

/// stdout / stderr 스트림 이벤트 페이로드 (`kalsae.process.stdout` / `kalsae.process.stderr`).
struct KSProcessDataEvent: Codable, Sendable {
    /// 프로세스 핸들 ID.
    var handle: String
    /// Base64 인코딩된 청크 데이터.
    var data: String
}

/// 프로세스 종료 이벤트 페이로드 (`kalsae.process.exit`).
struct KSProcessExitEvent: Codable, Sendable {
    var handle: String
    var code: Int32?
    var signal: Int32?
}

// MARK: - IPC 인수 구조체

struct KSWriteArg: Codable, Sendable {
    var handle: String
    var data: String  // base64
}

struct KSKillArg: Codable, Sendable {
    var handle: String
}

struct KSWaitArg: Codable, Sendable {
    var handle: String
}
