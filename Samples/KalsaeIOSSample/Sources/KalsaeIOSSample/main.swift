// KalsaeIOSSample/main.swift
//
// iOS 샘플 진입점. `KSApp.bootFromBundle` 가 SwiftPM 리소스 번들에 포함된
// `Resources/kalsae.json` 을 자동으로 찾아 부팅한 뒤, `app.run()` 이
// `KSiOSDemoHost.runMessageLoop()` ??`UIApplicationMain` 으로 진입한다.
//
// iOS 라이프사이클은 `UIApplicationDelegate` 가 소유하므로 `app.run()` 은
// 정상 흐름에서 반환되지 않는다 (Android 와 달리 호스트 측 Activity 가
// 아닌 Kalsae 가 내부적으로 `UIApplicationMain` 을 호출함).
//
// 사용자 코드는 부팅 클로저에서 명령을 등록하면 된다 - 웹뷰 측에서는
// `await window.__KS_.invoke("greet", { name: "iOS" })` 로 호출 가능.

import Foundation
import Kalsae  // `@_exported import KalsaeCore` / `KalsaeMacros` 포함

// MARK: - @KSCommand IPC

struct GreetOut: Codable, Sendable {
    let message: String
}

@KSCommand
func greet(name: String?) -> GreetOut {
    GreetOut(message: "Hello, \(name ?? "iOS")!")
}

// MARK: - Entry point

@main
struct KalsaeIOSSampleApp {
    @MainActor
    static func main() async {
        do {
            let app = try await KSApp.bootFromBundle(
                resourceBundle: .module
            ) { registry in
                // @KSCommand 매크로가 생성하는 등록 함수.
                await _ksRegister_greet(into: registry)
            }
            // UIApplicationMain 으로 진입 - 반환되지 않음.
            _ = app.run()
        } catch {
            // 부팅 실패 시 NSLog 로 콘솔에 남기고 비정상 종료.
            // (`print` 는 iOS 시뮬레이터/디바이스 콘솔에서 보이지 않을 수 있음.)
            NSLog("KalsaeIOSSample boot failed: %@", String(describing: error))
            exit(1)
        }
    }
}
