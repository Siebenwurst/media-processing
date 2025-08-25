extension PNGMetadata {
    /// A color precision descriptor.
    ///
    /// This type models the information stored in an ``Chunk/sBIT`` chunk.
    struct SignificantBits {
        /// The value of this color precision descriptor.
        let `case`: Case

        /// A color precision case. This is a separate type for validation purposes.
        enum Case {
            /// A color precision descriptor for a grayscale image.
            /// -   Parameter _:
            ///     The number of significant bits in each grayscale sample.
            ///
            ///     This value must be greater than zero, and can be no greater
            ///     than the color depth of the image color format.
            case v(Int)
            /// A color precision descriptor for a grayscale-alpha image.
            /// -   Parameter _:
            ///     The number of significant bits in each grayscale and alpha
            ///     sample, respectively.
            ///
            ///     Both precision values must be greater than zero, and neither
            ///     can be greater than the color depth of the image color format.
            case va((v: Int, a: Int))
            /// A color precision descriptor for an RGB, BGR, or indexed image.
            /// -   Parameter _:
            ///     The number of significant bits in each red, green, and blue
            ///     sample, respectively. If the image uses an indexed color format,
            ///     the precision values refer to the precision of the palette
            ///     entries, not the indices. The ``Chunk/sBIT`` chunk type is
            ///     not capable of specifying the precision of the alpha component
            ///     of the palette entries. If the image palette was augmented with
            ///     alpha samples from a ``Transparency`` descriptor, the precision
            ///     of those samples is left undefined.
            ///
            ///     The meaning of a color precision descriptor is
            ///     poorly-defined for BGR images. It is strongly recommended that
            ///     iphone-optimized images use ``PNG/SignificantBits`` only if all
            ///     samples have the same precision.
            ///
            ///     Each precision value must be greater than zero, and none of them
            ///     can be greater than the color depth of the image color format.
            case rgb((r: Int, g: Int, b: Int))
            /// A color precision descriptor for an RGBA or BGRA image.
            /// -   Parameter _:
            ///     The number of significant bits in each red, green, blue, and alpha
            ///     sample, respectively.
            ///
            ///     The meaning of a color precision descriptor is
            ///     poorly-defined for BGRA images. It is strongly recommended that
            ///     iphone-optimized images use ``PNG/SignificantBits`` only if all
            ///     samples have the same precision.
            ///
            ///     Each precision value must be greater than zero, and none of them
            ///     can be greater than the color depth of the image color format.
            case rgba((r: Int, g: Int, b: Int, a: Int))
        }
    }
}

extension PNGMetadata.SignificantBits {
    /// Creates a color precision descriptor by parsing the given chunk data,
    /// interpreting and validating it according to the given `pixel` format.
    /// -   Parameter data:
    ///     The contents of an ``Chunk/sBIT`` chunk to parse.
    /// -   Parameter pixel:
    ///     The pixel format specifying how the chunk data is to be interpreted
    ///     and validated against.
    init(parsing data: [UInt8], pixel: PNGFormat.Pixel) throws {
        let arity: Int = (pixel.hasColor ? 3 : 1) + (pixel.hasAlpha ? 1 : 0)
        guard data.count == arity else {
            throw PNGImage.ParsingError.invalidSignificantBitsChunkLength(data.count, expected: arity)
        }

        let precision: [Int]
        switch pixel {
        case .v1, .v2, .v4, .v8, .v16:
            let v = Int(data[0])
            self.case = .v(v)
            precision = [v]

        case .rgb8, .rgb16, .indexed1, .indexed2, .indexed4, .indexed8:
            let r = Int(data[0]), g = Int(data[1]), b = Int(data[2])
            self.case = .rgb((r, g, b))
            precision = [r, g, b]

        case .va8, .va16:
            let v = Int(data[0]), a = Int(data[1])
            self.case = .va((v, a))
            precision = [v, a]

        case .rgba8, .rgba16:
            let r = Int(data[0]), g = Int(data[1]), b = Int(data[2]), a = Int(data[3])
            self.case = .rgba((r, g, b, a))
            precision = [r, g, b, a]
        }

        let max: Int
        switch pixel {
        case .indexed1, .indexed2, .indexed4, .indexed8:
            max = 8
        default:
            max = pixel.depth
        }
        for v in precision where !(1 ... max ~= v) {
            throw PNGImage.ParsingError.invalidSignificantBitsPrecision(v, max: max)
        }
    }
}

extension PNGMetadata.SignificantBits: CustomStringConvertible {
    var description: String {
        let channels: [(String, Int)]
        switch self.case {
        case .v(let v):
            channels = [("v", v)]
        case .va(let (v, a)):
            channels = [("v", v), ("a", a)]
        case .rgb(let (r, g, b)):
            channels = [("r", r), ("g", g), ("b", b)]
        case .rgba(let (r, g, b, a)):
            channels = [("r", r), ("g", g), ("b", b), ("a", a)]
        }
        return """
        PNG.\(Self.self) (\(PNGChunkIdentifier.sBIT))
        {
        \(channels.map{ "    \($0.0): \($0.1)" }.joined(separator: "\n"))
        }
        """
    }
}
