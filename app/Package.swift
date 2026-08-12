// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EnglishCompanion",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EnglishCompanionCore", targets: ["EnglishCompanionCore"]),
        .executable(name: "EnglishCompanion", targets: ["EnglishCompanion"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/jamesrochabrun/SwiftOpenAI.git",
            exact: "4.5.1"
        ),
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(
            name: "EnglishCompanionCore",
            dependencies: [
                "CSQLite",
                .product(name: "SwiftOpenAI", package: "SwiftOpenAI"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "EnglishCompanion",
            dependencies: ["EnglishCompanionCore"]
        ),
        .testTarget(
            name: "EnglishCompanionCoreTests",
            dependencies: [
                "EnglishCompanionCore",
                .product(name: "SwiftOpenAI", package: "SwiftOpenAI"),
            ]
        ),
    ]
)
