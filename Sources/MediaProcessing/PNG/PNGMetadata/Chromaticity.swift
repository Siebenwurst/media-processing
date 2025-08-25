extension PNGMetadata {
    /// A chromaticity descriptor.
    ///
    /// This type models the information stored in a ``Chunk/cHRM`` chunk.
    struct Chromaticity {
        /// The white point of an image, expressed as a pair of fractions.
        let w: (x: Percentmille, y: Percentmille)
        /// The chromaticity of the red component of an image,
        /// expressed as a pair of fractions.
        let r: (x: Percentmille, y: Percentmille)
        /// The chromaticity of the green component of an image,
        /// expressed as a pair of fractions.
        let g: (x: Percentmille, y: Percentmille)
        /// The chromaticity of the blue component of an image,
        /// expressed as a pair of fractions.
        let b: (x: Percentmille, y: Percentmille)
    }
}

extension PNGMetadata.Chromaticity {
    /// Creates a chromaticity descriptor by parsing the given chunk data.
    /// -   Parameter data:
    ///     The contents of a ``Chunk/cHRM`` chunk to parse.
    init(parsing data:[UInt8]) throws {
        guard data.count == 32 else {
            throw PNGImage.ParsingError.invalidChromaticityChunkLength(data.count)
        }

        self.w.x = .init(data.load(bigEndian: UInt32.self, as: Int.self, at:  0))
        self.w.y = .init(data.load(bigEndian: UInt32.self, as: Int.self, at:  4))
        self.r.x = .init(data.load(bigEndian: UInt32.self, as: Int.self, at:  8))
        self.r.y = .init(data.load(bigEndian: UInt32.self, as: Int.self, at: 12))
        self.g.x = .init(data.load(bigEndian: UInt32.self, as: Int.self, at: 16))
        self.g.y = .init(data.load(bigEndian: UInt32.self, as: Int.self, at: 20))
        self.b.x = .init(data.load(bigEndian: UInt32.self, as: Int.self, at: 24))
        self.b.y = .init(data.load(bigEndian: UInt32.self, as: Int.self, at: 28))
    }
}

extension PNGMetadata.Chromaticity: CustomStringConvertible {
    var description:String {
        """
        PNG.\(Self.self) (\(PNGChunkIdentifier.cHRM))
        {
            w           : \(self.w)
            r           : \(self.r)
            g           : \(self.g)
            b           : \(self.b)
        }
        """
    }
}
