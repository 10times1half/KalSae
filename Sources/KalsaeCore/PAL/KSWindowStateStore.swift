public import Foundation

/// Persistent record of a window's geometry between launches.
///
/// Files live under `%APPDATA%\<identifier>\window-state.json` (Windows)
/// or `~/Library/Application Support/<identifier>/window-state.json`
/// (macOS) / `~/.config/<identifier>/window-state.json` (Linux).
///
/// The file holds a dictionary keyed by window label so multi-window
/// apps can persist each window independently.
public struct KSPersistedWindowState: Codable, Sendable, Equatable {
    /// Window left edge, in screen pixels (DPI-aware coordinates).
    public var x: Int
    /// Window top edge, in screen pixels.
    public var y: Int
    /// Window width, in screen pixels.
    public var width: Int
    /// Window height, in screen pixels.
    public var height: Int
    /// `true` when the window was maximized at the time of save.
    public var maximized: Bool
    /// `true` when the window was full-screen at the time of save.
    /// Restored apps re-enter full-screen post-show.
    public var fullscreen: Bool

    public init(
        x: Int = 0, y: Int = 0,
        width: Int = 800, height: Int = 600,
        maximized: Bool = false,
        fullscreen: Bool = false
    ) {
        self.x = x; self.y = y
        self.width = width; self.height = height
        self.maximized = maximized
        self.fullscreen = fullscreen
    }
}

/// File-backed store for `KSPersistedWindowState` entries. Atomic on
/// writes, best-effort on reads (a corrupted or missing file simply
/// yields `nil` for the requested label so the caller falls back to
/// config defaults).
public struct KSWindowStateStore: Sendable {
    /// Absolute path of the JSON file backing this store.
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Convenience constructor: builds the canonical
    /// `<appSupport>/<identifier>/window-state.json` URL and creates
    /// the parent directory if missing. Errors fall back to a no-op
    /// store rooted at the temp directory so the caller never crashes
    /// on first launch.
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

    /// Returns the persisted state for `label`, or `nil` when the file
    /// does not exist, the JSON is malformed, or the label has no
    /// matching entry.
    public func load(label: String) -> KSPersistedWindowState? {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder()
                .decode([String: KSPersistedWindowState].self, from: data)
        else { return nil }
        return dict[label]
    }

    /// Persists `state` for `label`, merging into the existing dict.
    /// Failures surface via the returned `Bool` — the host should not
    /// crash if the disk is full or the directory has been deleted
    /// between launches.
    @discardableResult
    public func save(label: String, state: KSPersistedWindowState) -> Bool {
        var dict: [String: KSPersistedWindowState] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONDecoder()
            .decode([String: KSPersistedWindowState].self, from: data) {
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
