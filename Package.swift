// swift-tools-version: 6.1
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
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "MediaProcessing",
            dependencies: [
                .product(name: "_NIOFileSystem", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                "_LZ77", "_Hashing", "_MediaProcessingShims"
            ],
        ),
        .target(name: "_LZ77", dependencies: ["_Hashing"], path: "Sources/LZ77"),
        .target(name: "_Hashing", path: "Sources/Hashing"),

        .target(name: "_MediaProcessingShims"),

        .testTarget(
            name: "MediaProcessingTests",
            dependencies: ["MediaProcessing", .product(name: "_NIOFileSystem", package: "swift-nio"),],
            resources: [.copy("Files/img.png")]
        ),
    ]
)
