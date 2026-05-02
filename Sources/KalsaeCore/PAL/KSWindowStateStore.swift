/// 론치 간 윈돈우 기하학의 영속 레코드.
///
/// 파일 위치: Windows는 `%APPDATA%\<identifier>\window-state.json`,
/// macOS는 `~/Library/Application Support/<identifier>/window-state.json`,
/// Linux는 `~/.config/<identifier>/window-state.json`.
///
/// 파일은 윈돈우 레이블로 키징된 사전을 보유하여
/// 멀티 윈돈우 앱이 각 윈돈우를 독립적으로 저장할 수 있다.
public import Foundation

/// `KSPersistedWindowState` 항목의 파일 기반 저장소. 쓰기는 원자적,
/// 읽기는 최선 노력(파일이 손상되었거나 없는 경우 요청된 레이블에
/// 대해 `nil`을 반환하여 호출자가 config 기본값으로 폴백하도록 한다).
public struct KSPersistedWindowState: Codable, Sendable, Equatable {
    /// 윈돈우 왼쪽 가장자리, 화면 픽셀(공백 인식 춨표).
    public var x: Int
    /// 윈돈우 위쪽 가장자리, 화면 픽셀.
    public var y: Int
    /// 윈돈우 너비, 화면 픽셀.
    public var width: Int
    /// 윈돈우 높이, 화면 픽셀.
    public var height: Int
    /// `true`이면 저장 시점에 윈돈우가 최대화되어 있었다.
    public var maximized: Bool
    /// `true`이면 저장 시점에 윈돈우가 전체 화면이었다.
    /// 복원된 앱은 표시 후 전체 화면으로 재진입한다.
    public var fullscreen: Bool

    public init(
        x: Int = 0, y: Int = 0,
        width: Int = 800, height: Int = 600,
        maximized: Bool = false,
        fullscreen: Bool = false
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.maximized = maximized
        self.fullscreen = fullscreen
    }
}
public struct KSWindowStateStore: Sendable {
    /// 이 저장소를 뒷받침하는 JSON 파일의 절대 경로.
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// 편의 생성자: 캐노니컹 `<appSupport>/<identifier>/window-state.json` URL을
    /// 구성하고 없으면 상위 디렉토리를 생성한다. 오류 발생 시는 입시
    /// 디렉토리에 루팅된 no-op 저장소로 폴백하여 첫 실행 시
    /// 호출자가 크래시되지 않도록 한다.
    public static func standard(forIdentifier identifier: String) -> KSWindowStateStore {
        let fm = FileManager.default
        let base: URL
        do {
            base = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true)
        } catch {
            return KSWindowStateStore(
                url: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("\(identifier)-window-state.json"))
        }
        let dir = base.appendingPathComponent(identifier, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return KSWindowStateStore(
            url: dir.appendingPathComponent("window-state.json"))
    }

    /// `label`에 해당하는 저장된 상태를 반환하여, 파일이 없거나
    /// JSON이 손상되었거나 해당 레이블에 대한 항목이 없으면 `nil`을 반환한다.
    public func load(label: String) -> KSPersistedWindowState? {
        guard let data = try? Data(contentsOf: url),
            let dict = try? JSONDecoder()
                .decode([String: KSPersistedWindowState].self, from: data)
        else { return nil }
        return dict[label]
    }

    /// `label`에 대한 `state`를 기존 딕셔너리에 병합하여 저장한다.
    /// 반환된 `Bool`로 실패 여부를 알 수 있다 — 디스크가 꽉 찼거나
    /// 디렉토리가 실행 중 삭제된 경우에도 호스트는 크래시하지 않아야 한다.
    @discardableResult
    public func save(label: String, state: KSPersistedWindowState) -> Bool {
        var dict: [String: KSPersistedWindowState] = [:]
        if let data = try? Data(contentsOf: url),
            let existing = try? JSONDecoder()
                .decode([String: KSPersistedWindowState].self, from: data)
        {
            dict = existing
        }
        dict[label] = state
        guard let data = try? JSONEncoder().encode(dict) else { return false }
        // Windows의 Defender / Search Indexer 등이 일시적으로 파일을 잠그는
        // 경우가 있어 atomic 쓰기 실패 시 비-atomic으로 폴백한다.
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            do {
                try data.write(to: url, options: [])
                return true
            } catch {
                return false
            }
        }
    }
}
