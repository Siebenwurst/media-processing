extension PNGMetadata {
    /// A gamma descriptor.
    ///
    /// This type models the information stored in a ``Chunk/gAMA`` chunk.
    struct Gamma {
        /// The gamma value of an image, expressed as a fraction.
        let value: Percentmille
    }
}

extension PNGMetadata.Gamma {
    /// Creates a gamma descriptor by parsing the given chunk data.
    /// -   Parameter data:
    ///     The contents of a ``Chunk/gAMA`` chunk to parse.
    init(parsing data:[UInt8]) throws {
        guard data.count == 4 else {
            throw PNGImage.ParsingError.invalidGammaChunkLength(data.count)
        }

        self.value = .init(data.load(bigEndian: UInt32.self, as: Int.self, at: 0))
    }
}

extension PNGMetadata.Gamma: CustomStringConvertible {
    var description:String {
        """
        PNG.\(Self.self) (\(PNGChunkIdentifier.gAMA)) {
            value: \(self.value)
        }
        """
    }
}
