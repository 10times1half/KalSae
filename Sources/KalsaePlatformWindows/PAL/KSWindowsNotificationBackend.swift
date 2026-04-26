#if os(Windows)
internal import WinSDK
internal import CKalsaeWV2
public import KalsaeCore
public import Foundation

/// Win32 desktop notifications.
///
/// Two delivery paths:
/// 1. **WinRT toast** (`Windows.UI.Notifications.ToastNotificationManager`)
///    when an AppUserModelID has been registered via
///    `setAppUserModelID(_:)`. This is the modern Windows 10/11 toast
///    experience, including Action Center persistence.
/// 2. **Tray balloon** (`Shell_NotifyIconW` with `NIF_INFO`) as a fallback
///    when no AUMID is set or the WinRT call fails (e.g. AUMID has no
///    Start Menu shortcut on a development machine).
public final class KSWindowsNotificationBackend: KSNotificationBackend, @unchecked Sendable {
    @MainActor private weak var tray: KSWindowsTrayBackend?
    @MainActor private var aumid: String?

    public init() {}

    /// Optional. When set, balloon-fallback notifications reuse the
    /// tray's persistent icon instead of installing a transient one.
    @MainActor
    public func attachTray(_ tray: KSWindowsTrayBackend?) {
        self.tray = tray
    }

    /// Registers the AppUserModelID for toast notifications. Without
    /// a matching Start Menu shortcut Windows silently drops the toast,
    /// so the backend transparently falls back to balloon tips when the
    /// WinRT call fails.
    @MainActor
    public func setAppUserModelID(_ aumid: String) {
        self.aumid = aumid
        aumid.withCString(encodedAs: UTF16.self) { ptr in
            _ = KSWV2_SetAppUserModelID(ptr)
        }
    }

    public func requestPermission() async -> Bool {
        // Win32 알림은 별도의 권한 부여 절차가 없다.
        true
    }

    public func post(_ notification: KSNotification) async throws(KSError) {
        let result: Result<Void, KSError> = await MainActor.run {
            self._postResult(notification)
        }
        try result.unwrap()
    }

    public func cancel(id: String) async {
        // 태그/그룹으로 속애어 취소는 후속 단계에서 구현.
    }

    /// Synchronous, UI-thread entry point used by `KSApp.postNotification`.
    @MainActor
    public func postOnUI(_ n: KSNotification) {
        do {
            try _postOnMain(n)
        } catch {
            print("KSWindowsNotificationBackend.postOnUI failed: \(error)")
        }
    }

    @MainActor
    private func _postResult(_ n: KSNotification) -> Result<Void, KSError> {
        // `_postOnMain` is `throws(KSError)` only — bare catch auto-binds.
        do { try _postOnMain(n); return .success(()) }
        catch { return .failure(error) }
    }

    @MainActor
    private func _postOnMain(_ n: KSNotification) throws(KSError) {
        // 1. AUMID가 등록되어 있으면 WinRT 토스트를 먼저 시도한다.
        if let aumid {
            let hr = aumid.withCString(encodedAs: UTF16.self) { aumidPtr -> Int32 in
                n.title.withCString(encodedAs: UTF16.self) { titlePtr in
                    let body = n.body ?? ""
                    return body.withCString(encodedAs: UTF16.self) { bodyPtr in
                        KSWV2_ShowToast(aumidPtr, titlePtr, bodyPtr)
                    }
                }
            }
            if hr >= 0 { return }   // S_OK or S_FALSE
            // 실패 시 버블로 폴백한다.
        }

        // 2. 트레이를 통한 버블 폴백.
        if let tray, tray.showBalloon(
            title: n.title,
            message: n.body ?? "",
            kind: .info)
        {
            return
        }

        // 3. 일회성 일시 트레이.
        let transient = KSWindowsTrayBackend()
        let cfg = KSTrayConfig(
            icon: n.iconPath ?? "",
            tooltip: n.title,
            menu: nil,
            onLeftClick: nil)
        try transient.installSync(cfg)
        guard transient.showBalloon(
            title: n.title,
            message: n.body ?? "",
            kind: .info)
        else {
            transient.removeSync()
            throw KSError(code: .platformInitFailed,
                          message: "Failed to post notification (balloon)")
        }
        let box = KSSendableBox(transient)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            box.value.removeSync()
        }
    }
}
#endif
