#if os(iOS)
internal import UIKit
public import KalsaeCore

/// `KSiOSDemoHost.runMessageLoop()`에서
/// `KSiOSAppDelegate.application(_:didFinishLaunchingWithOptions:)`로
/// 부팅 시 상태를 운반하는 공유 싱글톤.
///
/// Windows에서 전역 `Win32App.shared`를, macOS에서 `KSMacApp.shared`를 사용해
/// UIKit이 엔트리 포인트 인수를 전달하지 않는 한계를 우회하는
/// 패턴과 동일하다.
@MainActor
internal final class KSiOSRuntime {
    static let shared = KSiOSRuntime()
    private init() {}

    var pendingDemoHost: KSiOSDemoHost?
}
#endif
