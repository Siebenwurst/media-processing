// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "media-processing",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MediaProcessing", targets: ["MediaProcessing"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.86.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.3"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "MediaProcessing",
            dependencies: [
                .product(name: "_NIOFileSystem", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                "_LZ77", "_Hashing", "_NumericsShims"
            ],
            swiftSettings: [.strictMemorySafety()]
        ),
        .target(name: "_LZ77", dependencies: ["_Hashing"], path: "Sources/LZ77", swiftSettings: [.strictMemorySafety()]),
        .target(name: "_Hashing", path: "Sources/Hashing", swiftSettings: [.strictMemorySafety()]),

        .target(name: "_NumericsShims"),

        .testTarget(name: "MediaProcessingTests", dependencies: ["MediaProcessing"]),
    ]
)
