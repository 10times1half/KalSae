#if os(Linux)
internal import CKalsaeGtk
public import KalsaeCore
public import Foundation

/// `KSAcceleratorBackend`의 Linux 구현 — 윈도우-스코프 단축키 전용.
///
/// `GtkShortcutController`(scope=LOCAL)에 부착되며, 활성 윈도우가
/// 포커스를 가질 때만 발동한다. 시스템-와이드 글로벌 단축키는 v1
/// 범위 외이며, Wayland 표준 부재로 추후 별도 RFC에서 다룬다.
@MainActor
public final class KSLinuxAcceleratorBackend: KSAcceleratorBackend {
    /// 트램폴린 컨텍스트 보유. C측은 unowned 포인터로 들고 있으므로
    /// 등록된 동안만 살아 있어야 한다.
    private var entries: [String: Unmanaged<KSLinuxAcceleratorEntryBox>] = [:]

    public nonisolated init() {}

    public func register(id: String,
                         accelerator: String,
                         _ handler: @Sendable @escaping () -> Void) async throws(KSError) {
        guard let trigger = Self.toGtkTrigger(accelerator) else {
            throw KSError(code: .invalidArgument,
                          message: "Could not parse accelerator: \(accelerator)")
        }
        guard let host = Self.activeHostPtr() else {
            throw KSError(code: .platformInitFailed,
                          message: "No active window to attach accelerator to")
        }

        // 이전 등록 해제(트램폴린 박스 정리).
        if let old = entries.removeValue(forKey: id) {
            ks_gtk_host_uninstall_accelerator(host, id)
            old.release()
        }

        let box = KSLinuxAcceleratorEntryBox(handler)
        let um = Unmanaged.passRetained(box)
        let rc = ks_gtk_host_install_accelerator(
            host, id, trigger,
            linuxAcceleratorTrampoline,
            um.toOpaque())
        guard rc != 0 else {
            um.release()
            throw KSError(code: .invalidArgument,
                          message: "Failed to install accelerator: \(accelerator)")
        }
        entries[id] = um
    }

    public func unregister(id: String) async throws(KSError) {
        guard let um = entries.removeValue(forKey: id) else { return }
        if let host = Self.activeHostPtr() {
            ks_gtk_host_uninstall_accelerator(host, id)
        }
        um.release()
    }

    public func unregisterAll() async throws(KSError) {
        if let host = Self.activeHostPtr() {
            ks_gtk_host_uninstall_all_accelerators(host)
        }
        for (_, um) in entries { um.release() }
        entries.removeAll()
    }

    // MARK: - 헬퍼

    private static func activeHostPtr() -> OpaquePointer? {
        guard let handle = KSLinuxHandleRegistry.shared.allHandles().first,
              let entry  = KSLinuxHandleRegistry.shared.entry(for: handle)
        else { return nil }
        return entry.host.hostPtr
    }

    /// 크로스플랫폼 가속기 표기(`"Ctrl+Shift+K"`)를 GTK 트리거 문자열
    /// (`"<Control><Shift>k"`)로 변환한다. 알 수 없는 토큰이 있으면 nil.
    /// 키 토큰은 GDK key name으로 그대로 전달된다(`F1`, `Plus`, `space` 등).
    internal static func toGtkTrigger(_ accel: String) -> String? {
        let tokens = accel.split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !tokens.isEmpty else { return nil }

        var modifiers: [String] = []
        var key: String?

        for token in tokens {
            switch token.lowercased() {
            case "cmd", "command", "super", "meta":
                modifiers.append("<Super>")
            case "cmdorctrl", "commandorcontrol", "ctrl", "control":
                modifiers.append("<Control>")
            case "shift":
                modifiers.append("<Shift>")
            case "alt", "option":
                modifiers.append("<Alt>")
            default:
                guard key == nil else { return nil }
                key = token
            }
        }
        guard let key, !key.isEmpty else { return nil }

        // 단일 문자는 GTK가 소문자 keyname을 기대하므로 정규화.
        // `F1`, `Plus`, `space` 등 다중 문자는 그대로 보존.
        let normalizedKey: String = {
            if key.count == 1 { return key.lowercased() }
            return key
        }()
        return modifiers.joined() + normalizedKey
    }
}

/// C 트램폴린: GTK 메인 스레드에서 호출됨.
private let linuxAcceleratorTrampoline: @convention(c) (
    UnsafeMutableRawPointer?
) -> Int32 = { ctx in
    guard let ctx else { return 0 }
    let box = Unmanaged<KSLinuxAcceleratorEntryBox>
        .fromOpaque(ctx).takeUnretainedValue()
    box.handler()
    return 1   // 이벤트 소비
}

/// 위 트램폴린이 들고 있는 박스. C에 unowned 포인터로 전달되며,
/// `KSLinuxAcceleratorBackend.entries`가 수명을 보유한다.
internal final class KSLinuxAcceleratorEntryBox: @unchecked Sendable {
    let handler: @Sendable () -> Void
    init(_ h: @escaping @Sendable () -> Void) { self.handler = h }
}
#endif
