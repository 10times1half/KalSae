// swift-tools-version:6.0
// Kalsae - Swift Backend + Web Frontend = Beautiful Desktop Apps
// License: MIT
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Kalsae",
    platforms: [
        .macOS(.v14)
        // Windows 10 1809+ and Linux (GTK4 + WebKitGTK 6.0) are implicit;
        // SwiftPM`s `platforms:` only declares Apple platform minimums.
    ],
    products: [
        .library(name: "Kalsae", targets: ["Kalsae"]),
        .library(name: "KalsaeCore", targets: ["KalsaeCore"]),
        .library(name: "KalsaeMacros", targets: ["KalsaeMacros"]),
        .executable(name: "kalsae-demo", targets: ["KalsaeDemo"]),
        .executable(name: "kalsae", targets: ["KalsaeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git",
                 from: "600.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git",
                 from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "KalsaeCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/KalsaeCore",
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "CKalsaeWV2",
            path: "Sources/CKalsaeWV2",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../Vendor/WebView2/build/native/include"),
                .define("UNICODE"),
                .define("_UNICODE"),
                .define("_WIN32_WINNT", to: "0x0A00"),
            ],
            linkerSettings: [
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                .linkedLibrary("advapi32", .when(platforms: [.windows])),
                .linkedLibrary("version", .when(platforms: [.windows])),
                .linkedLibrary("shlwapi", .when(platforms: [.windows])),
                .linkedLibrary("shell32", .when(platforms: [.windows])),
                .unsafeFlags(
                    ["-L", "Vendor/WebView2/build/native/x64"],
                    .when(platforms: [.windows])),
                .linkedLibrary(
                    "WebView2LoaderStatic",
                    .when(platforms: [.windows])),
                .linkedLibrary("runtimeobject", .when(platforms: [.windows])),
            ]
        ),
        .systemLibrary(
            name: "CGtk4",
            path: "Sources/CGtk4",
            pkgConfig: "gtk4",
            providers: [
                .apt(["libgtk-4-dev"]),
            ]
        ),
        .systemLibrary(
            name: "CWebKitGTK",
            path: "Sources/CWebKitGTK",
            pkgConfig: "webkitgtk-6.0",
            providers: [
                .apt(["libwebkitgtk-6.0-dev"]),
            ]
        ),
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
        .target(
            name: "KalsaePlatformMac",
            dependencies: ["KalsaeCore"],
            path: "Sources/KalsaePlatformMac",
            swiftSettings: commonSwiftSettings
        ),
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
                .linkedLibrary("user32", .when(platforms: [.windows])),
                .linkedLibrary("gdi32", .when(platforms: [.windows])),
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                .linkedLibrary("comctl32", .when(platforms: [.windows])),
            ]
        ),
        .target(
            name: "KalsaePlatformLinux",
            dependencies: [
                "KalsaeCore",
                .target(name: "CKalsaeGtk",
                        condition: .when(platforms: [.linux])),
            ],
            path: "Sources/KalsaePlatformLinux",
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "Kalsae",
            dependencies: [
                "KalsaeCore",
                "KalsaeMacros",
                .target(name: "KalsaePlatformMac",
                        condition: .when(platforms: [.macOS])),
                .target(name: "KalsaePlatformWindows",
                        condition: .when(platforms: [.windows])),
                .target(name: "KalsaePlatformLinux",
                        condition: .when(platforms: [.linux])),
            ],
            path: "Sources/Kalsae",
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "KalsaeMacros",
            dependencies: [
                "KalsaeCore",
                "KalsaeMacrosPlugin",
            ],
            path: "Sources/KalsaeMacros",
            swiftSettings: commonSwiftSettings
        ),
        .macro(
            name: "KalsaeMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ],
            path: "Sources/KalsaeMacrosPlugin"
        ),
        .target(
            name: "KalsaeCLICore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/KalsaeCLI/Support",
            resources: [.copy("Templates")],
            swiftSettings: commonSwiftSettings
        ),
        .executableTarget(
            name: "KalsaeCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "KalsaeCLICore",
                "KalsaeCore",
            ],
            path: "Sources/KalsaeCLI",
            exclude: ["Support"],
            sources: ["KalsaeCLI.swift", "Commands"],
            swiftSettings: commonSwiftSettings
        ),
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
            resources: [.copy("Resources")],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "KalsaeCLITests",
            dependencies: ["KalsaeCLICore"],
            path: "Tests/KalsaeCLITests",
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "KalsaeCoreTests",
            dependencies: ["KalsaeCore"],
            path: "Tests/KalsaeCoreTests",
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "KalsaeMacrosTests",
            dependencies: [
                "KalsaeMacrosPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport",
                         package: "swift-syntax"),
            ],
            path: "Tests/KalsaeMacrosTests"
        ),
    ]
)

var commonSwiftSettings: [SwiftSetting] {
    [
        .swiftLanguageMode(.v6),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]
}
