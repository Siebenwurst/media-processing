import Testing
import _NIOFileSystem

@testable import MediaProcessing

import func Foundation.getenv
import class Foundation.Bundle

@Test func resolveFilePaths() {
    let processor = ImageProcessor()

    let paths1 = processor.makePaths(for: "/var/www/assets/image.jpeg", format: nil)
    #expect(paths1.filePath == "/var/www/assets/tn_image.jpeg")
    #expect(paths1.filePathWildcard == "/var/www/assets/tn_%s.jpeg")

    let paths2 = processor.makePaths(for: "/var/www/assets/image.jpeg", format: "png")
    #expect(paths2.filePath == "/var/www/assets/tn_image.jpeg.png")
    #expect(paths2.filePathWildcard == "/var/www/assets/tn_%s.png")
}

@Test func parseDimensions() {
    let processor = ImageProcessor()

    let width = processor.parseDimension(from: "  width: 180   ")
    let height = processor.parseDimension(from: "   height: 180")
    #expect(width == 180)
    #expect(height == 180)
}

@Test func thumbnailForPNG() async throws {
    let processor = ImageProcessor(executablePath: env("VIPS_LOCATION").flatMap({ .init($0) }))

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

func env(_ name: String) -> String? {
    getenv(name).flatMap { String(cString: $0) }
}

struct TestingError: Error {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}
