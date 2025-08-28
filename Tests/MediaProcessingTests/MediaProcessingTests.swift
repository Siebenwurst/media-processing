import Testing
@testable import MediaProcessing

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
