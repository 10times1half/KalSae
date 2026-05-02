#if os(macOS)
    internal import AppKit
    public import KalsaeCore

    /// `KSWindowHandle`을 macOS `NSWindow`로 변환한다.
    ///
    /// 다이얼로그, 메뉴, 트레이, 셸 등 모든 PAL 백엔드가 모달 호출의
    /// 부모 윈도우를 찾는 데 사용한다. Windows 측의 `KSWin32HandleRegistry`와 대응한다.
    @MainActor
    internal final class KSMacHandleRegistry {
        static let shared = KSMacHandleRegistry()

        private var byLabel: [String: KSMacWindow] = [:]
        private var byRawValue: [UInt64: KSMacWindow] = [:]

        private init() {}

        func register(label: String, rawValue: UInt64, window: KSMacWindow) {
            byLabel[label] = window
            byRawValue[rawValue] = window
        }

        func unregister(label: String) {
            guard let w = byLabel.removeValue(forKey: label) else { return }
            if let key = byRawValue.first(where: { $0.value === w })?.key {
                byRawValue.removeValue(forKey: key)
            }
        }

        func window(for handle: KSWindowHandle) -> KSMacWindow? {
            if let w = byLabel[handle.label] { return w }
            return byRawValue[handle.rawValue]
        }

        func handle(for label: String) -> KSWindowHandle? {
            guard let w = byLabel[label] else { return nil }
            return KSWindowHandle(
                label: label,
                rawValue: UInt64(UInt(bitPattern: ObjectIdentifier(w))))
        }

        func allWindows() -> [KSMacWindow] {
            Array(byLabel.values)
        }
    }
#endif
