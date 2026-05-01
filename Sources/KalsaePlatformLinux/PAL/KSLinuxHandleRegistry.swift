#if os(Linux)
public import KalsaeCore

@MainActor
internal final class KSLinuxHandleRegistry {
    internal struct Entry {
        let handle: KSWindowHandle
        let host: GtkWebViewHost
    }

    static let shared = KSLinuxHandleRegistry()

    private var byLabel: [String: Entry] = [:]
    private var byRawValue: [UInt64: Entry] = [:]

    private init() {}

    func register(label: String, host: GtkWebViewHost) -> KSWindowHandle {
        let raw = UInt64(UInt(bitPattern: ObjectIdentifier(host)))
        let handle = KSWindowHandle(label: label, rawValue: raw)
        let entry = Entry(handle: handle, host: host)
        byLabel[label] = entry
        byRawValue[raw] = entry
        return handle
    }

    func unregister(_ handle: KSWindowHandle) {
        if let removed = byLabel.removeValue(forKey: handle.label) {
            byRawValue.removeValue(forKey: removed.handle.rawValue)
            return
        }
        byRawValue.removeValue(forKey: handle.rawValue)
    }

    func entry(for handle: KSWindowHandle) -> Entry? {
        if let entry = byLabel[handle.label] { return entry }
        return byRawValue[handle.rawValue]
    }

    func handle(for label: String) -> KSWindowHandle? {
        byLabel[label]?.handle
    }

    func allHandles() -> [KSWindowHandle] {
        Array(byLabel.values.map(\.handle))
    }
}
#endif
