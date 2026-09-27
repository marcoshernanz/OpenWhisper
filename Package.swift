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
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0")
    ],
    targets: [
        .target(
            name: "OpenWhisperCore",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .target(
            name: "OpenWhisperObjC"
        ),
        .executableTarget(
            name: "OpenWhisper",
            dependencies: ["OpenWhisperCore", "OpenWhisperObjC"]
        ),
        .testTarget(
            name: "OpenWhisperCoreTests",
            dependencies: ["OpenWhisperCore"]
        ),
        .testTarget(
            name: "OpenWhisperObjCTests",
            dependencies: ["OpenWhisperObjC"]
        )
    ]
)
