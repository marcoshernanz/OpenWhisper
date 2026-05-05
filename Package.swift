// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenWhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenWhisper", targets: ["OpenWhisper"]),
        .library(name: "OpenWhisperCore", targets: ["OpenWhisperCore"])
    ],
    targets: [
        .target(name: "OpenWhisperCore"),
        .executableTarget(
            name: "OpenWhisper",
            dependencies: ["OpenWhisperCore"]
        ),
        .testTarget(
            name: "OpenWhisperCoreTests",
            dependencies: ["OpenWhisperCore"]
        )
    ]
)
