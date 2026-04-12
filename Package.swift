// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "THOR",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "THORApp", targets: ["THORApp"]),
        .executable(name: "THORCore", targets: ["THORCore"]),
        .executable(name: "thorctl", targets: ["THORctl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.5.0"),
    ],
    targets: [
        // Shared library — models, database, keychain, SSH utilities
        .target(
            name: "THORShared",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/THORShared"
        ),

        // Background helper service — SSH, transfers, job queue
        .executableTarget(
            name: "THORCore",
            dependencies: ["THORShared"],
            path: "Sources/THORCore"
        ),

        // Main SwiftUI application
        .executableTarget(
            name: "THORApp",
            dependencies: ["THORShared"],
            path: "Sources/THORApp",
            exclude: ["Resources"]
        ),

        // CLI tool for managing THOR devices from terminal
        .executableTarget(
            name: "THORctl",
            dependencies: ["THORShared"],
            path: "Sources/THORctl"
        ),

        // Tests
        .testTarget(
            name: "THORTests",
            dependencies: ["THORShared", "THORApp"],
            path: "Tests/THORTests"
        ),
    ]
)
