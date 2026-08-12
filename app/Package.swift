// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EnglishCompanion",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EnglishCompanionCore", targets: ["EnglishCompanionCore"]),
        .executable(name: "EnglishCompanion", targets: ["EnglishCompanion"]),
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(
            name: "EnglishCompanionCore",
            dependencies: ["CSQLite"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "EnglishCompanion",
            dependencies: ["EnglishCompanionCore"]
        ),
        .testTarget(
            name: "EnglishCompanionCoreTests",
            dependencies: ["EnglishCompanionCore"]
        ),
    ]
)
