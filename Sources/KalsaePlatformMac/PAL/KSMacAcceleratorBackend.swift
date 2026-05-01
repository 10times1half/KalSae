#if os(macOS)
internal import AppKit
public import KalsaeCore

/// NSEvent 모니터를 사용하는 `KSAcceleratorBackend`의 macOS 구현체.
@MainActor
public final class KSMacAcceleratorBackend: KSAcceleratorBackend {
    private struct Entry {
        let handler: @Sendable () -> Void
        let flags: NSEvent.ModifierFlags
        let keyEquivalent: String
    }

    private var entries: [String: Entry] = [:]
    private var localMonitor: Any?
    private var globalMonitor: Any?

    public nonisolated init() {}

    public func register(id: String,
                         accelerator: String,
                         _ handler: @Sendable @escaping () -> Void) async throws(KSError) {
        try await unregister(id: id)

        guard let parsed = parseAccelerator(accelerator) else {
            throw KSError(code: .invalidArgument,
                          message: "Could not parse accelerator: \(accelerator)")
        }

        entries[id] = Entry(handler: handler,
                            flags: parsed.flags,
                            keyEquivalent: parsed.key)
        installMonitorsIfNeeded()
    }

    public func unregister(id: String) async throws(KSError) {
        entries.removeValue(forKey: id)
    }

    public func unregisterAll() async throws(KSError) {
        entries.removeAll()
    }

    // MARK: - 모니터 관리

    private func installMonitorsIfNeeded() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
            return event
        }
        for entry in entries.values {
            if entry.flags == flags && (entry.keyEquivalent == chars || entry.keyEquivalent == "") {
                // 기능 키 확인
                if entry.keyEquivalent.isEmpty { continue }
                entry.handler()
                return nil // 이벤트를 소비한다
            }
        }
        return event
    }

    // MARK: - 파서

    private struct ParsedAccel {
        let flags: NSEvent.ModifierFlags
        let key: String
    }

    private func parseAccelerator(_ accel: String) -> ParsedAccel? {
        let tokens = accel.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !tokens.isEmpty else { return nil }

        var flags: NSEvent.ModifierFlags = []
        var key: String?

        for token in tokens {
            switch token.lowercased() {
            case "cmd", "command", "super", "meta", "cmdorctrl", "commandorcontrol":
                flags.insert(.command)
            case "shift":
                flags.insert(.shift)
            case "alt", "option":
                flags.insert(.option)
            case "ctrl", "control":
                flags.insert(.control)
            default:
                guard key == nil else { return nil }
                key = token.lowercased()
            }
        }

        guard let key else { return nil }
        return ParsedAccel(flags: flags, key: key)
    }
}
#endif