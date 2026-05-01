public import Foundation
public import KalsaeCore

#if os(Windows)
internal import KalsaePlatformWindows
#endif

// MARK: - UI 스레드 편의 헬퍼
//
// 백그라운드 컨텍스트(예: `Task.detached`에서 돌아가는 IPC 디스패치
// 핸들러)에서 호출된 명령이 데드락 없이 네이티브 UI를 조작할 수
// 있도록 `postJob → @MainActor sync 호출` 패턴을 감싼다. Win32 메시지
// 루프는 Swift의 협동 스케줄러를 펄프하지 않으므로 백그라운드에서의
// `await MainActor.run`은 재개되지 않지만, PostMessageW(WM_USER+1)은
// 재개된다.

extension KSApp {

    /// 네이티브 메시지 대화상자를 표시한다. `completion`은 사용자가
    /// 대화상자를 닫은 후 UI 스레드에서 실행된다. 모든 스레드에서
    /// 안전하게 호출할 수 있다.
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

    /// 네이티브 파일 열기 대화상자를 표시한다. `completion`은 선택된
    /// URL을 받는다 (사용자가 취소하면 빈 배열).
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

    /// 네이티브 데스크톱 알림을 게시한다. 발사 후 망각(Fire-and-forget).
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

    /// AppUserModelID를 등록해 이후 `postNotification` 호출이 레거시
    /// 풍선 도움말 대신 최신 WinRT 토스트 파이프라인을 사용하도록 한다.
    /// 일치하는 시작 메뉴 바로가기가 없으면 Windows가 자동으로 토스트를
    /// 삭제하므로, 백엔드는 실패 시 자동으로 풍선 도움말로 폴백한다.
    ///
    /// Windows 외 플랫폼에서는 아무 동작도 하지 않는다.
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
