// swift-tools-version:6.0
// Kalsae iOS 샘플 ?? SwiftPM 독립 패키지.
//
// 빌드 흐름 (macOS 호스트 필요 ??iOS Mach-O 컴파일 + .app 서명/설치):
//   1) iOS 시뮬레이터(arm64)용 실행 파일 빌드
//        swift build --package-path Samples/KalsaeIOSSample \
//            --triple arm64-apple-ios16.0-simulator -c release \
//            --product KalsaeIOSSample
//      혹은 실기기(arm64):
//        swift build --package-path Samples/KalsaeIOSSample \
//            --triple arm64-apple-ios16.0 -c release \
//            --product KalsaeIOSSample
//
//   2) Kalsae CLI 로 .app 번들 생성 (호스트 OS 무관 ??순수 string emit)
//        kalsae build --ios \
//            --ios-executable Samples/KalsaeIOSSample/.build/<triple>/release/KalsaeIOSSample
//      산출: dist/ios-KalsaeIOSSample-<ver>/KalsaeIOSSample.app
//
//   3) 시뮬레이터 설치 / 실행 (macOS + Xcode 필요)
//        xcrun simctl install booted dist/ios-KalsaeIOSSample-<ver>/KalsaeIOSSample.app
//        xcrun simctl launch booted io.kalsae.iossample
//
// 실기기 / App Store 배포는 Xcode 프로젝트 + `kalsae build --store ios-appstore`
// 파이프라인(`Sources/KalsaeCLI/Support/PackagerIOS.swift`) 을 별도로 사용한다.
//
// 안드로이드 샘플과 동일하게 `kalsae.json` 과 프론트엔드는 SwiftPM 리소스로
// 함께 빌드되어 `KSApp.bootFromBundle(resourceBundle: .module)` 가 찾는다.
import PackageDescription

let package = Package(
    name: "KalsaeIOSSample",
    platforms: [
        .iOS(.v16)
    ],
    dependencies: [
        // 루트 Kalsae 패키지를 상대 경로로 의존.
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "KalsaeIOSSample",
            dependencies: [
                // `Kalsae` 가 `KalsaeMacros` 와 `KalsaeCore` 를 `@_exported` 로 재노출하므로
                // 단일 의존만 추가하면 `@KSCommand` 매크로까지 사용할 수 있다.
                .product(name: "Kalsae", package: "Kalsae"),
            ],
            path: "Sources/KalsaeIOSSample",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
