#if os(Linux)
internal import CKalsaeGtk
internal import Logging
public import KalsaeCore
public import Foundation

/// `KSTrayBackend`의 Linux 구현 — D-Bus StatusNotifierItem + DBusMenu 직접 노출.
///
/// AppIndicator3 / libayatana 의존성 없이 GIO `GDBusConnection`만 사용한다.
/// 동작하는 데스크톱: KDE Plasma, Cinnamon, XFCE, Pantheon, AppIndicator
/// extension이 활성화된 GNOME. Watcher 부재 시 install은 throw하지 않고
/// 경고 로그만 남기고 no-op으로 폴백한다.
///
/// 메뉴 구조는 평탄(서브메뉴 미지원)이며, 서브메뉴 항목은 부모 라벨만
/// 포함되고 자식은 무시된다(v1 스코프).
@MainActor
public final class KSLinuxTrayBackend: KSTrayBackend {
    private var trayPtr: OpaquePointer?
    private var onLeftClickCommand: String?
    /// 트램폴린이 unowned 포인터로 들고 있으므로 수명 보유.
    private var contextBox: Unmanaged<KSLinuxTrayBox>?

    public nonisolated init() {}

    public func install(_ config: KSTrayConfig) async throws(KSError) {
        // 기존 인스턴스가 있으면 먼저 제거.
        await removeInternal()

        let tray = ks_gtk_tray_new()
        guard let tray else {
            throw KSError(code: .platformInitFailed,
                          message: "ks_gtk_tray_new returned NULL")
        }

        let appId = Bundle.main.bundleIdentifier ?? "kalsae"
        let iconPath = Self.resolveIconPath(config.icon)
        let tooltip  = config.tooltip ?? ""

        // 메뉴 평탄화. 첫 깊이만 사용.
        let flat = Self.flattenMenu(config.menu ?? [])

        let box = KSLinuxTrayBox(onLeftClick: config.onLeftClick)
        let unmanaged = Unmanaged.passRetained(box)

        let rc = Self.withCItems(flat) { itemsPtr, count in
            ks_gtk_tray_install(
                tray,
                appId,
                iconPath,
                tooltip,
                itemsPtr, Int32(count),
                linuxTrayActivateTrampoline,
                unmanaged.toOpaque())
        }

        self.trayPtr = tray
        self.contextBox = unmanaged
        self.onLeftClickCommand = config.onLeftClick

        if rc == 0 {
            // Watcher 부재 — 객체는 등록되어 있으나 셸이 픽업하지 못함.
            // throw 하지 않고 best-effort로 살려둔다.
            KSLog.logger("platform.linux.tray").warning(
                "StatusNotifierWatcher unavailable (no compatible shell extension). Tray installed but may not be visible.")
        }
    }

    public func setTooltip(_ tooltip: String) async throws(KSError) {
        guard let trayPtr else { return }
        ks_gtk_tray_set_tooltip(trayPtr, tooltip)
    }

    public func setMenu(_ items: [KSMenuItem]) async throws(KSError) {
        guard let trayPtr else { return }
        let flat = Self.flattenMenu(items)
        Self.withCItems(flat) { itemsPtr, count in
            ks_gtk_tray_set_menu(trayPtr, itemsPtr, Int32(count))
        }
    }

    public func remove() async {
        await removeInternal()
    }

    // MARK: - Private helpers

    private func removeInternal() async {
        if let trayPtr {
            ks_gtk_tray_free(trayPtr)
            self.trayPtr = nil
        }
        if let box = contextBox {
            box.release()
            self.contextBox = nil
        }
        self.onLeftClickCommand = nil
    }

    /// 아이콘 경로 해석 — 절대 경로면 그대로, 상대 경로면 cwd 기준.
    /// 비어 있거나 nil이면 빈 문자열을 반환(셸 기본 아이콘 폴백).
    private static func resolveIconPath(_ icon: String?) -> String {
        guard let icon, !icon.isEmpty else { return "" }
        if icon.hasPrefix("/") { return icon }
        let cwd = FileManager.default.currentDirectoryPath
        return cwd + "/" + icon
    }

    /// `KSMenuItem` 트리를 평탄 항목 리스트로 변환한다. 서브메뉴는
    /// 라벨만 보존하고 자식은 무시(v1 스코프). 구분선은 그대로 통과.
    fileprivate struct FlatItem {
        let label: String
        let commandID: String
        let enabled: Bool
        let isSeparator: Bool
    }

    private static func flattenMenu(_ items: [KSMenuItem]) -> [FlatItem] {
        var out: [FlatItem] = []
        for item in items {
            switch item.kind {
            case .separator:
                out.append(FlatItem(label: "", commandID: "",
                                    enabled: false, isSeparator: true))
            case .action:
                out.append(FlatItem(
                    label: item.label ?? "",
                    commandID: item.command ?? item.id ?? "",
                    enabled: item.enabled,
                    isSeparator: false))
            case .submenu:
                // 서브메뉴는 v1 스코프 외 — 라벨만 비활성 항목으로 보임.
                out.append(FlatItem(
                    label: (item.label ?? "") + " ▸",
                    commandID: "",
                    enabled: false,
                    isSeparator: false))
            }
        }
        return out
    }

    /// 평탄 항목 배열을 C 구조체 배열로 변환해 클로저에 전달한다.
    /// 모든 문자열 포인터는 클로저 호출 동안만 유효하다.
    private static func withCItems<R>(
        _ items: [FlatItem],
        _ body: (UnsafePointer<KSGtkTrayMenuItem>?, Int) -> R
    ) -> R {
        if items.isEmpty {
            return body(nil, 0)
        }
        // 각 문자열을 별도 cString으로 보관 → 라이프타임을 클로저 호출까지.
        var labelStrs: [UnsafeMutablePointer<CChar>?] = []
        var cmdStrs: [UnsafeMutablePointer<CChar>?] = []
        labelStrs.reserveCapacity(items.count)
        cmdStrs.reserveCapacity(items.count)

        var cItems: [KSGtkTrayMenuItem] = []
        cItems.reserveCapacity(items.count)

        for item in items {
            let l = strdup(item.label)
            let c = strdup(item.commandID)
            labelStrs.append(l)
            cmdStrs.append(c)
            cItems.append(KSGtkTrayMenuItem(
                label: UnsafePointer(l),
                command_id: UnsafePointer(c),
                enabled: item.enabled ? 1 : 0,
                is_separator: item.isSeparator ? 1 : 0))
        }

        let result = cItems.withUnsafeBufferPointer { buf in
            body(buf.baseAddress, items.count)
        }
        for p in labelStrs { free(p) }
        for p in cmdStrs   { free(p) }
        return result
    }
}

/// 트램폴린이 unowned 포인터로 보유하는 박스.
internal final class KSLinuxTrayBox: @unchecked Sendable {
    let onLeftClick: String?
    init(onLeftClick: String?) { self.onLeftClick = onLeftClick }
}

/// C 트램폴린 — `command_id`가 빈 문자열이면 SNI Activate(좌클릭),
/// 그렇지 않으면 메뉴 항목 클릭. 메인 스레드에서 호출된다.
private let linuxTrayActivateTrampoline: @convention(c) (
    UnsafePointer<CChar>?,
    UnsafeMutableRawPointer?
) -> Void = { commandIdPtr, ctx in
    guard let ctx else { return }
    let box = Unmanaged<KSLinuxTrayBox>
        .fromOpaque(ctx).takeUnretainedValue()

    let commandId: String = {
        guard let p = commandIdPtr else { return "" }
        return String(cString: p)
    }()

    MainActor.assumeIsolated {
        if commandId.isEmpty {
            // Activate(좌클릭) — onLeftClick 라우팅.
            if let cmd = box.onLeftClick, !cmd.isEmpty {
                KSLinuxCommandRouter.shared.dispatch(
                    command: cmd, itemID: nil)
            }
        } else {
            // 메뉴 항목 클릭 → 명령 디스패치.
            KSLinuxCommandRouter.shared.dispatch(
                command: commandId, itemID: nil)
        }
    }
}
#endif
