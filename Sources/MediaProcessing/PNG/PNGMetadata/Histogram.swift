extension PNGMetadata {
    /// A palette frequency histogram.
    ///
    /// This type models the information stored in a ``Chunk/hIST`` chunk.
    struct Histogram {
        /// The frequency values of this histogram.
        ///
        /// The *i*th frequency value corresponds to the *i*th entry in the
        /// image palette.
        let frequencies:[UInt16]
    }
}

extension PNGMetadata.Histogram {
    /// Creates a palette histogram by parsing the given chunk data,
    /// validating it according to the given image `palette`.
    /// -   Parameter data:
    ///     The contents of a ``Chunk/hIST`` chunk to parse.
    /// -   Parameter palette:
    ///     The image palette the chunk data is to be validated against.
    init(parsing data: [UInt8], palette: PNGPalette) throws {
        guard data.count == 2 * palette.entries.count else {
            throw PNGImage.ParsingError.invalidHistogramChunkLength(data.count, expected: 2 * palette.entries.count)
        }
        self.frequencies = (0 ..< data.count >> 1).map {
            data.load(bigEndian: UInt16.self, as: UInt16.self, at: $0 << 1)
        }
    }
}
extension PNGMetadata.Histogram: CustomStringConvertible {
    var description: String {
        """
        PNG.\(Self.self) (\(PNGChunkIdentifier.hIST)) {
            frequencies: <\(self.frequencies.count) entries>
        }
        """
    }
}
