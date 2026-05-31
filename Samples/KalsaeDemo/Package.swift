// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KalsaeDemo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "kalsae-demo", targets: ["KalsaeDemo"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "KalsaeDemo",
            dependencies: [
                .product(name: "Kalsae", package: "Kalsae")
            ],
            path: "Sources/KalsaeDemo",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
