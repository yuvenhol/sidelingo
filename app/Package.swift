// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SideLingo",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SideLingoCore", targets: ["SideLingoCore"]),
        .executable(name: "SideLingo", targets: ["SideLingo"]),
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
            name: "SideLingoCore",
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
            name: "SideLingo",
            dependencies: ["SideLingoCore"]
        ),
        .testTarget(
            name: "SideLingoCoreTests",
            dependencies: [
                "SideLingoCore",
                .product(name: "SwiftOpenAI", package: "SwiftOpenAI"),
            ]
        ),
    ]
)
