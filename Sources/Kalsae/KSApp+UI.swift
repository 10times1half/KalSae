public import Foundation
public import KalsaeCore

#if os(Windows)
internal import KalsaePlatformWindows
#endif

// MARK: - UI-thread convenience helpers
//
// 백그라운드 컨텍스트(예: `Task.detached`에서 돌아가는 IPC 디스패치
// 핸들러)에서 호출된 명령이 데드락 없이 네이티브 UI를 조작할 수
// 있도록 `postJob → @MainActor sync 호출` 패턴을 감싼다. Win32 메시지
// 루프는 Swift의 협동 스케줄러를 펄프하지 않으므로 백그라운드에서의
// `await MainActor.run`은 재개되지 않지만, PostMessageW(WM_USER+1)은
// 재개된다.

extension KSApp {

    /// Shows a native message dialog. `completion` runs on the UI thread
    /// after the user dismisses the dialog. Safe to call from any thread.
    nonisolated public func showMessage(
        _ options: KSMessageOptions,
        completion: @MainActor @Sendable @escaping (KSMessageResult) -> Void = { _ in }
    ) {
        #if os(Windows)
        postJob {
            let result = KSWindowsDialogBackend.messageOnUI(options)
            completion(result)
        }
        #else
        KSLog.logger("kalsae.app").info(
            "showMessage is not implemented on this platform yet")
        _ = options
        _ = completion
        #endif
    }

    /// Shows a native open-file dialog. `completion` receives the picked
    /// URLs (empty when the user cancelled).
    nonisolated public func openFile(
        _ options: KSOpenFileOptions,
        completion: @MainActor @Sendable @escaping ([URL]) -> Void
    ) {
        #if os(Windows)
        postJob {
            let urls = KSWindowsDialogBackend.openFileOnUI(options)
            completion(urls)
        }
        #else
        KSLog.logger("kalsae.app").info(
            "openFile is not implemented on this platform yet")
        _ = options
        // 플랫폼 미구현 시 호출자가 영구히 대기하지 않도록 빈 결과로 콜백한다.
        Task { @MainActor in completion([]) }
        #endif
    }

    /// Posts a native desktop notification. Fire-and-forget.
    nonisolated public func postNotification(_ n: KSNotification) {
        #if os(Windows)
        let platform = self.platform
        postJob {
            // 플랫폼 알림 백엔드를 재사용해 (부팅 시 `tray.install`로 설치한)
            // 상주 트레이 아이콘을 경유해 전달한다.
            if let nbackend = platform.notifications as? KSWindowsNotificationBackend {
                nbackend.postOnUI(n)
            }
        }
        #else
        KSLog.logger("kalsae.app").info(
            "notifications are not implemented on this platform yet")
        _ = n
        #endif
    }

    /// Registers an AppUserModelID so subsequent `postNotification` calls
    /// use the modern WinRT toast pipeline instead of legacy balloon
    /// tips. Without a matching Start Menu shortcut Windows silently
    /// drops the toast, so the backend automatically falls back to
    /// balloons on failure.
    ///
    /// On non-Windows platforms this is a no-op.
    @MainActor
    public func setAppUserModelID(_ aumid: String) {
        #if os(Windows)
        if let nbackend = platform.notifications as? KSWindowsNotificationBackend {
            nbackend.setAppUserModelID(aumid)
        }
        #else
        _ = aumid
        #endif
    }
}
