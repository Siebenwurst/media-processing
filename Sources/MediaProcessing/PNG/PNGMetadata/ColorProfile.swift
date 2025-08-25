import _LZ77

extension PNGMetadata {
    /// An embedded color profile.
    ///
    /// This type models the information stored in an ``Chunk/iCCP`` chunk.
    struct ColorProfile {
        /// The name of this profile.
        let name: String
        /// The uncompressed [ICC](http://www.color.org/index.xalter) color
        /// profile data.
        let profile: [UInt8]
    }
}

extension PNGMetadata.ColorProfile {
    /// Creates a color profile by parsing the given chunk data.
    /// -   Parameter data:
    ///     The contents of an ``Chunk/iCCP`` chunk to parse.
    init(parsing data:[UInt8]) throws {
        //  ┌ ╶ ╶ ╶ ╶ ╶ ╶┬───┬───┬ ╶ ╶ ╶ ╶ ╶ ╶ ╶ ╶ ╶ ╶ ╶ ╶┐
        //  │    name    │ 0 │ M │        profile         │
        //  └ ╶ ╶ ╶ ╶ ╶ ╶┴───┴───┴ ╶ ╶ ╶ ╶ ╶ ╶ ╶ ╶ ╶ ╶ ╶ ╶┘
        //               k  k+1 k+2
        let k: Int

        (self.name, k) = try PNGMetadata.Text.name(parsing: data[...]) {
            PNGImage.ParsingError.invalidColorProfileName($0)
        }

        // assert existence of method byte
        guard k + 1 < data.endIndex else {
            throw PNGImage.ParsingError.invalidColorProfileChunkLength(data.count, min: k + 2)
        }

        guard data[k + 1] == 0 else {
            throw PNGImage.ParsingError.invalidColorProfileCompressionMethodCode(data[k + 1])
        }

        var inflator: LZ77.Inflator = .init()
        guard case nil = try inflator.push(data.dropFirst(k + 2)) else {
            throw PNGImage.ParsingError.incompleteColorProfileCompressedDatastream
        }

        self.profile = inflator.pull()
    }
}

extension PNGMetadata.ColorProfile: CustomStringConvertible {
    var description:String
    {
        """
        PNG.\(Self.self) (\(PNGChunkIdentifier.iCCP)) {
            name: '\(self.name)'
            profile: <\(self.profile.count) bytes>
        }
        """
    }
}
