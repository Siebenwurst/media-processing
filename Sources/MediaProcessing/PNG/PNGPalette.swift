/// An image palette.
///
/// This type models the information stored in a ``Chunk/PLTE`` chunk.
/// This information is used to populate the non-alpha components of the
/// `palette` field in an image color ``Format``, when appropriate.
struct PNGPalette {
    /// The entries in this palette.
    let entries: [(r: UInt8, g: UInt8, b: UInt8)]
}

extension PNGPalette {
    /// Creates an image palette by parsing the given chunk data, interpreting
    /// and validating it according to the given `pixel` format.
    /// -   Parameter data:
    ///     The contents of a ``Chunk/PLTE`` chunk to parse.
    /// -   Parameter pixel:
    ///     The pixel format specifying how the chunk data is to be interpreted.
    init(parsing data: [UInt8], pixel: PNGFormat.Pixel) throws {
        guard pixel.hasColor else {
            throw PNGImage.ParsingError.unexpectedPalette(pixel: pixel)
        }

        let (count, remainder):(Int, Int) = data.count.quotientAndRemainder(dividingBy: 3)
        guard remainder == 0 else {
            throw PNGImage.ParsingError.invalidPaletteChunkLength(data.count)
        }

        // check number of palette entries
        let max: Int = 1 << Swift.min(pixel.depth, 8)
        guard 1 ... max ~= count else {
            throw PNGImage.ParsingError.invalidPaletteCount(count, max: max)
        }

        self.entries = stride(from: data.startIndex, to: data.endIndex, by: 3).map { (base: Int) in
            (r: data[base], g: data[base + 1], b: data[base + 2])
        }
    }
}
