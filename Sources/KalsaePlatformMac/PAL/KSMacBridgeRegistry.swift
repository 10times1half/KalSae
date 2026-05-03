#if os(macOS)
    internal import AppKit
    public import KalsaeCore

    /// `KSWindowBackend.create(_:)`로 동적으로 만들어진 macOS 창의
    /// `WKBridge` 인스턴스를 라벨별로 보관하는 사이드 레지스트리.
    ///
    /// `WKBridge`는 deinit되면 IPC가 끊기므로 창의 수명 동안
    /// 강한 참조를 유지해야 한다. `KSMacWindowBackend`는 struct이고
    /// `KSMacHandleRegistry`는 `KSMacWindow`만 보관하므로 별도 보관소가 필요하다.
    @MainActor
    internal final class KSMacBridgeRegistry {
        static let shared = KSMacBridgeRegistry()

        private var byLabel: [String: WKBridge] = [:]

        private init() {}

        func register(label: String, bridge: WKBridge) {
            byLabel[label] = bridge
        }

        func unregister(label: String) {
            byLabel.removeValue(forKey: label)
        }
    }
#endif
