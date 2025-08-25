extension PNGMetadata {
    /// A color rendering mode.
    ///
    /// This type models the information stored in an ``Chunk/sRGB`` chunk.
    /// It is not recommended for the same image to include both a `ColorRendering`
    /// mode and a ``ColorProfile``.
    enum ColorRendering {
        /// The perceptual rendering mode.
        case perceptual
        /// The relative colorimetric rendering mode.
        case relative
        /// The saturation rendering mode.
        case saturation
        /// The absolute colorimetric rendering mode.
        case absolute
    }
}

extension PNGMetadata.ColorRendering {
    /// Creates a color rendering mode by parsing the given chunk data.
    /// -   Parameter data:
    ///     The contents of an ``Chunk/sRGB`` chunk to parse.
    init(parsing data:[UInt8]) throws {
        guard data.count == 1 else {
            throw PNGImage.ParsingError.invalidColorRenderingChunkLength(data.count)
        }

        switch data[0] {
        case 0: self = .perceptual
        case 1: self = .relative
        case 2: self = .saturation
        case 3: self = .absolute
        case let code:
            throw PNGImage.ParsingError.invalidColorRenderingCode(code)
        }
    }
}
extension PNGMetadata.ColorRendering: CustomStringConvertible {
    var description: String {
        """
        PNG.\(Self.self) (\(PNGChunkIdentifier.sRGB)) {
            \(self)
        }
        """
    }
}
