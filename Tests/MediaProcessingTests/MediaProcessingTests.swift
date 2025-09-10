import Testing
import Logging
import _NIOFileSystem

@testable import MediaProcessing

import func Foundation.getenv
import class Foundation.Bundle

let logger = {
    var logger = Logger(label: "ImageProcessor")
    logger.logLevel = .trace
    return logger
}()

let processor = ImageProcessor(logger: logger, executablePath: env("VIPS_LOCATION").flatMap({ .init($0) }))

@Test func resolveFilePaths() {
    let paths1 = processor.makePaths(for: "/var/www/assets/image.jpeg", format: nil)
    #expect(paths1.filePath == "/var/www/assets/tn_image.jpeg")
    #expect(paths1.filePathWildcard == "/var/www/assets/tn_%s.jpeg")

    let paths2 = processor.makePaths(for: "/var/www/assets/image.jpeg", format: "png")
    #expect(paths2.filePath == "/var/www/assets/tn_image.jpeg.png")
    #expect(paths2.filePathWildcard == "/var/www/assets/tn_%s.png")
}

@Test func parseDimensions() {
    let width = processor.parseDimension(from: "  width: 180   ")
    let height = processor.parseDimension(from: "   height: 180")
    #expect(width == 180)
    #expect(height == 180)
}

@Test func thumbnailForPNG() async throws {
    let path = try #require(Bundle.module.path(forResource: "img", ofType: "png"))
    let file = try await processor.compressImage(inputFile: .init(path), size: 1024)
    #expect(file.width == 1024 || file.height == 1024)
    let originalInfo = try await FileSystem.shared.info(forFileAt: .init(path))
    let compressedInfo = try await FileSystem.shared.info(forFileAt: file.0)

    guard let originalInfo, let compressedInfo else {
        throw TestingError("Failed to get file info")
    }

    print("original file size:", originalInfo.size)
    print("compress file size:", compressedInfo.size)
    #expect((originalInfo.size / 2) > compressedInfo.size)
}

@Test func thumbnailForPNGWithoutReturningSize() async throws {
    let path = try #require(Bundle.module.path(forResource: "img", ofType: "png"))
    let file = try await processor.compressImage(inputFile: .init(path), size: 1024, returnWithSize: false)
    #expect(file.width == 0 && file.height == 0)
    let originalInfo = try await FileSystem.shared.info(forFileAt: .init(path))
    let compressedInfo = try await FileSystem.shared.info(forFileAt: file.0)

    guard let originalInfo, let compressedInfo else {
        throw TestingError("Failed to get file info")
    }

    print("original file size:", originalInfo.size)
    print("compress file size:", compressedInfo.size)
    #expect((originalInfo.size / 2) > compressedInfo.size)
}

@Test func timeout() async throws {
    let path = try #require(Bundle.module.path(forResource: "img", ofType: "png"))
    await #expect(throws: ImageCompressionError.timeout, performing: {
        _ = try await processor.compressImage(inputFile: .init(path), size: 1024, timeout: .milliseconds(10))
    })
}

func env(_ name: String) -> String? {
    getenv(name).flatMap { String(cString: $0) }
}

struct TestingError: Error {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}
