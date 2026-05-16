// swift-tools-version:6.0
// Kalsae — Swift 백엔드 + 웹 프론트엔드 = 아름다운 데스크톱 앱
// License: MIT
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Kalsae",
    // ── 플랫폼 최소 버전 ───────────────────────────────────────────
    // Apple 플랫폼만 SwiftPM에서 명시적 선언이 가능.
    // Windows 10 1809+ 및 Linux(GTK4 + WebKitGTK 6.0)는 암시적으로 지원된다.
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
        // Windows 10 1809+ 및 Linux (GTK4 + WebKitGTK 6.0)는 암시적;
        // SwiftPM의 `platforms:`는 Apple 플랫폼 최소 버전만 선언한다.
    ],
    // ── 빌드 산출물 (Products) ─────────────────────────────────────
    // 외부 소비자가 사용할 수 있는 라이브러리 및 실행 파일
    products: [
        // 앱 개발자가 import Kalsae로 사용하는 최상위 퍼블릭 파사드 라이브러리
        .library(name: "Kalsae", targets: ["Kalsae"]),
        // IPC/Config/Asset/오류 처리 등 모든 플랫폼이 공유하는 코어 라이브러리
        .library(name: "KalsaeCore", targets: ["KalsaeCore"]),
        // @KSCommand 등 Consumer-facing 매크로를 내보내는 라이브러리
        .library(name: "KalsaeMacros", targets: ["KalsaeMacros"]),
        // 격리된 프로세스에서 실행되는 플러그인 호스트 라이브러리
        .library(name: "KalsaePluginProcess", targets: ["KalsaePluginProcess"]),
        // 실제 WebView 기반 데스크톱 앱을 시연하는 실행 파일
        .executable(name: "kalsae-demo", targets: ["KalsaeDemo"]),
        // 프로젝트 생성/빌드/개발 서버 등 개발자 도구 CLI 실행 파일
        .executable(name: "kalsae", targets: ["KalsaeCLI"]),
    ],
    // ── 외부 의존성 ────────────────────────────────────────────────
    dependencies: [
        // Apple의 구조화된 로깅 시스템 (OSLog보다 가벼운 순수 Swift 로거)
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        // Swift 소스 코드 파싱/분석/변환 라이브러리 (매크로 + 바인딩 생성기에서 사용)
        .package(url: "https://github.com/swiftlang/swift-syntax.git",
                 from: "603.0.0"),
        // 커맨드라인 인터페이스 파싱 (@Command, @Option, @Argument 등)
        .package(url: "https://github.com/apple/swift-argument-parser.git",
                 from: "1.3.0"),
    ],
    // ── 빌드 타겟 ──────────────────────────────────────────────────
    targets: [
        // ── KalsaeCore ────────────────────────────────────────────
        // 모든 플랫폼 PAL(PAL, Platform Abstraction Layer) 계층과
        // 공유되는 핵심 라이브러리: IPC, Config, Assets, 오류, 로깅 등
        .target(
            name: "KalsaeCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/KalsaeCore",
            swiftSettings: commonSwiftSettings
        ),

        // ── CKalsaeWV2 ───────────────────────────────────────────
        // Windows 전용 C++ 브리지. Swift에서 직접 호출 불가능한
        // Win32/COM/WebView2 API를 C로 감싸서 Swift에서 사용 가능하게 함.
        .target(
            name: "CKalsaeWV2",
            path: "Sources/CKalsaeWV2",
            exclude: [
                // kswv2_image.cpp / kswv2_visual.cpp로 대체된 레거시 소스
                // (commit 4a6497d "problem fix"에서 교체). 참고용으로 유지하되
                // 중복 심볼 링크 에러를 막기 위해 빌드에서 제외.
                "src/ksimage.cpp",
                "src/kswv2_capture.cpp",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                // WebView2 SDK 헤더 경로 (NuGet에서 Vendor/WebView2/로 fetch)
                .headerSearchPath("Vendor/WebView2/build/native/include"),
                // 유니코드 API 사용 (MessageBoxW 대신 MessageBoxA 등)
                .define("UNICODE"),
                .define("_UNICODE"),
                // Windows 10 1903+ (Win10 19H1) 타겟 (WebView2 최소 요구사항)
                .define("_WIN32_WINNT", to: "0x0A00"),
            ],
            linkerSettings: [
                // COM (Component Object Model) — WebView2 CoreWebView2 초기화
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                // 고급 Windows 서비스 (레지스트리, 보안, 계정 관리)
                .linkedLibrary("advapi32", .when(platforms: [.windows])),
                // 파일/제품 버전 정보 조회 (GetFileVersionInfo 등)
                .linkedLibrary("version", .when(platforms: [.windows])),
                // 경량 Shell 유틸리티 (PathFindFileName, SHGetValue 등)
                .linkedLibrary("shlwapi", .when(platforms: [.windows])),
                // Windows Shell API (SHGetKnownFolderPath, ShellExecute 등)
                .linkedLibrary("shell32", .when(platforms: [.windows])),
                // UUID/GUID 생성 및 변환 (UuidCreate, StringFromGUID2 등)
                .linkedLibrary("uuid", .when(platforms: [.windows])),
            ]
        ),

        // ── CGtk4 ────────────────────────────────────────────────
        // Linux 전용 GTK4 시스템 라이브러리. pkg-config로 시스템 패키지 검색.
        // modulemap을 통해 Swift에서 C API를 호출할 수 있게 함.
        .systemLibrary(
            name: "CGtk4",
            path: "Sources/CGtk4",
            pkgConfig: "gtk4",
            providers: [
                .apt(["libgtk-4-dev"]),
            ]
        ),

        // ── CWebKitGTK ───────────────────────────────────────────
        // Linux 전용 WebKitGTK 6.0 시스템 라이브러리.
        // pkg-config로 webkitgtk-6.0 패키지 검색.
        .systemLibrary(
            name: "CWebKitGTK",
            path: "Sources/CWebKitGTK",
            pkgConfig: "webkitgtk-6.0",
            providers: [
                .apt(["libwebkitgtk-6.0-dev"]),
            ]
        ),

        // ── CLibSecret ───────────────────────────────────────────
        // Linux 전용 libsecret-1 시스템 라이브러리 (Secret Service /
        // GNOME Keyring / KWallet 등 통합 자격증명 저장소).
        // pkg-config로 libsecret-1 패키지 검색. 별도 번들링/Vendor 없이
        // 시스템 동적 라이브러리에 동적 링크된다.
        .systemLibrary(
            name: "CLibSecret",
            path: "Sources/CLibSecret",
            pkgConfig: "libsecret-1",
            providers: [
                .apt(["libsecret-1-dev"]),
            ]
        ),

        // ── CKalsaeGtk ───────────────────────────────────────────
        // GTK4 + WebKitGTK의 C 함수를 Swift에서 호출 가능하게 감싸는
        // Linux 전용 브리지 타겟. Swift에서 직접 호출하기 어려운
        // GTK 시그널/콜백 등을 C에서 처리.
        .target(
            name: "CKalsaeGtk",
            dependencies: [
                .target(name: "CGtk4",
                        condition: .when(platforms: [.linux])),
                .target(name: "CWebKitGTK",
                        condition: .when(platforms: [.linux])),
            ],
            path: "Sources/CKalsaeGtk",
            publicHeadersPath: "include"
        ),

        // ── KalsaePlatformMac ─────────────────────────────────────
        // macOS PAL 구현 (AppKit + WKWebView).
        // 창/메뉴/시스템 트레이/알림/클립보드/딥링크 등 macOS 네이티브 기능 제공.
        .target(
            name: "KalsaePlatformMac",
            dependencies: ["KalsaeCore"],
            path: "Sources/KalsaePlatformMac",
            swiftSettings: commonSwiftSettings
        ),

        // ── KalsaePlatformWindows ─────────────────────────────────
        // Windows PAL 구현 (Win32 API + WebView2).
        // 창/메뉴/시스템 트레이/알림/레지스트리/딥링크 등 Windows 네이티브 기능 제공.
        .target(
            name: "KalsaePlatformWindows",
            dependencies: [
                "KalsaeCore",
                .target(name: "CKalsaeWV2",
                        condition: .when(platforms: [.windows])),
            ],
            path: "Sources/KalsaePlatformWindows",
            swiftSettings: commonSwiftSettings,
            linkerSettings: [
                // USER32 — 윈도우 생성/파괴/메시지 펌프 (CreateWindowEx, DefWindowProc 등)
                .linkedLibrary("user32", .when(platforms: [.windows])),
                // GDI32 — 기본 그래픽/텍스트 렌더링 (TextOut, GetDC 등)
                .linkedLibrary("gdi32", .when(platforms: [.windows])),
                // OLE32 — COM 초기화/해제 (CoInitializeEx, CoUninitialize)
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                // COMCTL32 — 공용 컨트롤 (ListView, TreeView 등 — 일부 대화상자에 사용)
                .linkedLibrary("comctl32", .when(platforms: [.windows])),
                // DWMAPI — Desktop Window Manager (창 테두리 다크모드, 제목 표시줄 색상 등)
                .linkedLibrary("dwmapi", .when(platforms: [.windows])),
            ]
        ),

        // ── KalsaePlatformLinux ───────────────────────────────────
        // Linux PAL 구현 (GTK4 + WebKitGTK 6.0).
        // 창/메뉴/시스템 트레이(D-Bus StatusNotifierItem)/알림/딥링크 등 Linux 네이티브 기능 제공.
        .target(
            name: "KalsaePlatformLinux",
            dependencies: [
                "KalsaeCore",
                .target(name: "CKalsaeGtk",
                        condition: .when(platforms: [.linux])),
                .target(name: "CLibSecret",
                        condition: .when(platforms: [.linux])),
            ],
            path: "Sources/KalsaePlatformLinux",
            swiftSettings: commonSwiftSettings
        ),

        // ── KalsaePlatformIOS ────────────────────────────────────
        // iOS PAL 구현 (UIKit + WKWebView).
        // iOS 앱 내에서 WebView 컨트롤러, 메뉴, 알림, 딥링크 등 iOS 네이티브 기능 제공.
        .target(
            name: "KalsaePlatformIOS",
            dependencies: ["KalsaeCore"],
            path: "Sources/KalsaePlatformIOS",
            swiftSettings: commonSwiftSettings
        ),

        // ── KalsaePlatformAndroid ─────────────────────────────────
        // Android PAL 구현 (JNI 브리지).
        // Android Activity/WebView와 Swift 간 JNI 인터페이스.
        // KSAndroidPlatform.run()은 영구 미지원 (JVM Activity 생명주기 문제).
        .target(
            name: "KalsaePlatformAndroid",
            dependencies: ["KalsaeCore"],
            path: "Sources/KalsaePlatformAndroid",
            swiftSettings: commonSwiftSettings
        ),

        // ── Kalsae (Public Facade) ────────────────────────────────
        // 모든 플랫폼 PAL + Core + Macros를 하나로 묶는 최상위 퍼블릭 인터페이스.
        // 앱 개발자는 이 타겟만 import 하면 됨.
        // 각 플랫폼 PAL은 조건부 의존성으로 해당 플랫폼에서만 빌드에 포함.
        .target(
            name: "Kalsae",
            dependencies: [
                "KalsaeCore",
                "KalsaeMacros",
                .target(name: "KalsaePlatformMac",
                        condition: .when(platforms: [.macOS])),
            .target(name: "KalsaePlatformIOS",
                condition: .when(platforms: [.iOS])),
            .target(name: "KalsaePlatformAndroid",
                condition: .when(platforms: [.android])),
                .target(name: "KalsaePlatformWindows",
                        condition: .when(platforms: [.windows])),
                .target(name: "KalsaePlatformLinux",
                        condition: .when(platforms: [.linux])),
            ],
            path: "Sources/Kalsae",
            swiftSettings: commonSwiftSettings
        ),

        // ── KalsaeMacros ─────────────────────────────────────────
        // Consumer-facing 매크로 라이브러리.
        // @KSCommand 등을 정의하며, 실제 구현은 KalsaeMacrosPlugin에 위임.
        // 앱 개발자는 이 타겟을 import하여 매크로 사용.
        .target(
            name: "KalsaeMacros",
            dependencies: [
                "KalsaeCore",
                "KalsaeMacrosPlugin",
            ],
            path: "Sources/KalsaeMacros",
            swiftSettings: commonSwiftSettings
        ),

        // ── KalsaeMacrosPlugin ───────────────────────────────────
        // SwiftSyntax 기반 매크로 구현체.
        // @KSCommand의 AST 변환, 진단(diagnostic) 메시지 등을 처리.
        .macro(
            name: "KalsaeMacrosPlugin",
            dependencies: [
                // Swift AST 타입 및 구문 노드 정의
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                // @main 진입점, @freestanding(expression) 등 매크로 프로토콜
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                // 컴파일러 플러그인 진입점 (createMacroExpansionContext 등)
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                // 컴파일 타임 오류/경고 진단 메시지 생성
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ],
            path: "Sources/KalsaeMacrosPlugin"
        ),

        // ── KalsaeCLICore ────────────────────────────────────────
        // CLI 내부 구현 라이브러리 (공유 로직).
        // 바인딩 생성기(BindingsGenerator), 패키저(Packager),
        // 프로젝트 템플릿(ProjectTemplate), 셸 유틸리티(Shell) 포함.
        // KalsaeCLI 실행파일과 테스트가 이 라이브러리를 공유.
        .target(
            name: "KalsaeCLICore",
            dependencies: [
                "KalsaeCore",
                // Swift 구문 분석기 (바인딩 생성기가 Swift 파일 파싱에 사용)
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/KalsaeCLI/Support",
            // kalsae new 명령어가 사용할 프로젝트 템플릿 디렉토리 (디렉토리 구조 보존)
            resources: [.copy("Templates")],
            swiftSettings: commonSwiftSettings
        ),

        // ── KalsaeCLI ────────────────────────────────────────────
        // kalsae 명령줄 도구 실행파일 진입점.
        // new / build / dev / generate / version 등 하위 명령어 포함.
        .executableTarget(
            name: "KalsaeCLI",
            dependencies: [
                // ArgumentParser의 @Command, @Option, @Argument 등
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "KalsaeCLICore",
                "KalsaeCore",
            ],
            path: "Sources/KalsaeCLI",
            // Support/ 디렉토리는 KalsaeCLICore 타겟이 이미 소유하므로 제외
            exclude: ["Support"],
            sources: ["KalsaeCLI.swift", "Commands"],
            swiftSettings: commonSwiftSettings
        ),

        // ── KalsaeDemo ───────────────────────────────────────────
        // 실행 가능한 데모 앱. WASM/HTML 리소스를 번들링하고
        // 각 플랫폼 PAL을 직접 참조하여 창 생성/메뉴/IPC 등 전체 기능 시연.
        .executableTarget(
            name: "KalsaeDemo",
            dependencies: [
                "Kalsae",
                .target(name: "KalsaePlatformWindows",
                        condition: .when(platforms: [.windows])),
                .target(name: "KalsaePlatformMac",
                        condition: .when(platforms: [.macOS])),
                .target(name: "KalsaePlatformLinux",
                        condition: .when(platforms: [.linux])),
            ],
            path: "Sources/KalsaeDemo",
            // 벤치마크 데이터 (빌드 시 불필요하므로 제외)
            exclude: ["dist-bench"],
            // 웹 프론트엔드 빌드 결과물 (HTML/CSS/JS 등)
            resources: [.copy("Resources")],
            swiftSettings: commonSwiftSettings
        ),

        // ── 테스트 타겟 ───────────────────────────────────────────

        // CLI 테스트: Packager, BindingsGenerator, ProjectTemplate 검증
        .testTarget(
            name: "KalsaeCLITests",
            dependencies: ["KalsaeCLICore", "KalsaeCore"],
            path: "Tests/KalsaeCLITests",
            swiftSettings: commonSwiftSettings
        ),

        // 코어 테스트: AssetCache/Resolver, IPC, Config, PAL 계약 테스트
        .testTarget(
            name: "KalsaeCoreTests",
            dependencies: ["KalsaeCore"],
            path: "Tests/KalsaeCoreTests",
            swiftSettings: commonSwiftSettings
        ),

        // 매크로 테스트: @KSCommand 확장 결과 + 진단 메시지 검증
        // SwiftSyntaxMacrosGenericTestSupport를 사용해 AST 출력 확인
        .testTarget(
            name: "KalsaeMacrosTests",
            dependencies: [
                "KalsaeMacrosPlugin",
                .product(name: "SwiftSyntaxMacroExpansion",
                         package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport",
                         package: "swift-syntax"),
            ],
            // commonSwiftSettings 사용 안 함: 매크로 테스트는 기본 언어모드로 충분
            path: "Tests/KalsaeMacrosTests"
        ),

        // Windows PAL 통합 테스트
        .testTarget(
            name: "KalsaePlatformWindowsTests",
            dependencies: [
                "KalsaePlatformWindows",
                "KalsaeCore",
            ],
            path: "Tests/KalsaePlatformWindowsTests",
            swiftSettings: commonSwiftSettings,
            linkerSettings: [
                .linkedLibrary("user32", .when(platforms: [.windows])),
                .linkedLibrary("gdi32", .when(platforms: [.windows])),
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                .linkedLibrary("comctl32", .when(platforms: [.windows])),
                .linkedLibrary("dwmapi", .when(platforms: [.windows])),
            ]
        ),

        // macOS PAL 통합 테스트
        .testTarget(
            name: "KalsaePlatformMacTests",
            dependencies: [
                "KalsaePlatformMac",
                "KalsaeCore",
            ],
            path: "Tests/KalsaePlatformMacTests",
            swiftSettings: commonSwiftSettings
        ),

        // Linux PAL 통합 테스트
        .testTarget(
            name: "KalsaePlatformLinuxTests",
            dependencies: [
                "KalsaePlatformLinux",
                "KalsaeCore",
            ],
            path: "Tests/KalsaePlatformLinuxTests",
            swiftSettings: commonSwiftSettings
        ),

        // iOS PAL 통합 테스트
        .testTarget(
            name: "KalsaePlatformIOSTests",
            dependencies: [
                "KalsaePlatformIOS",
                "KalsaeCore",
            ],
            path: "Tests/KalsaePlatformIOSTests",
            swiftSettings: commonSwiftSettings
        ),

        // Android PAL 통합 테스트 (Android 환경에서만 실행 가능)
        .testTarget(
            name: "KalsaePlatformAndroidTests",
            dependencies: [
                .target(name: "KalsaePlatformAndroid",
                        condition: .when(platforms: [.android])),
                "KalsaeCore",
            ],
            path: "Tests/KalsaePlatformAndroidTests",
            swiftSettings: commonSwiftSettings
        ),

        // ── KalsaePluginProcess ──────────────────────────────────
        // 격리된 프로세스에서 실행되는 플러그인 호스트.
        // 메인 앱 프로세스와 별도로 플러그인을 로드하여 안정성/보안성 확보.
        .target(
            name: "KalsaePluginProcess",
            dependencies: ["KalsaeCore"],
            path: "Sources/KalsaePluginProcess",
            swiftSettings: commonSwiftSettings
        ),

        // 플러그인 프로세스 통합 테스트
        .testTarget(
            name: "KalsaePluginProcessTests",
            dependencies: ["KalsaePluginProcess", "KalsaeCore"],
            path: "Tests/KalsaePluginProcessTests",
            swiftSettings: commonSwiftSettings
        ),
    ]
)

// ── 공통 Swift 컴파일러 설정 ───────────────────────────────────────
// 모든 Kalsae 타겟에 일괄 적용되는 빌드 설정.
var commonSwiftSettings: [SwiftSetting] {
    [
        // Swift 6 언어 모드 — 엄격한 동시성 검사, 데이터 경합 방지.
        // actor 격리, Sendable 검사, nonisolated 등 Swift 6 동시성 모델 채택.
        .swiftLanguageMode(.v6),

        // ExistentialAny — 프로토콜 타입 사용 시 반드시 'any' 키워드 명시.
        // AnyObject, any Equatable 등 명시적 표기로 가독성 및 안정성 향상.
        .enableUpcomingFeature("ExistentialAny"),

        // InternalImportsByDefault — public 모듈을 제외한 모든 import를
        // internal import로 처리하여 컴파일 시간 및 바이너리 크기 최적화.
        // public 타입을 노출하는 파일은 명시적으로 'public import' 필요.
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]
}
