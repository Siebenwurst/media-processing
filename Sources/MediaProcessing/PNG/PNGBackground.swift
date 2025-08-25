/// A background descriptor.
///
/// This type models the information stored in a ``Chunk/bKGD`` chunk.
/// This information is used to populate the `fill` field in
/// an image color ``Format``.
///
/// The value of this descriptor is stored in the ``PNG.Background/case``
/// property, after validation.
struct PNGBackground {
    /// The value of this background descriptor.
    let `case`: Case

    /// A background case. This is a separate type for validation purposes.
    enum Case {
        /// A background descriptor for an indexed image.
        /// -   Parameter index:
        ///     The index of the palette entry to be used as a background color.
        ///
        ///     This index must be within the index range of the image palette.
        case palette(index: Int)
        /// A background descriptor for an RGB, BGR, RGBA, or BGRA image.
        /// -   Parameter _:
        ///     A background color.
        ///
        ///     Note that the background components are unscaled samples. If
        ///     the image color depth is less than `16`, only the least-significant
        ///     bits of each sample are inhabited.
        case rgb((r: UInt16, g: UInt16, b: UInt16))
        /// A background descriptor for a grayscale or grayscale-alpha image.
        /// -   Parameter _:
        ///     A background color.
        ///
        ///     Note that the background value is an unscaled sample. If
        ///     the image color depth is less than `16`, only the least-significant
        ///     bits are inhabited.
        case v(UInt16)
    }
}

extension PNGBackground {
    /// Creates a background descriptor by parsing the given chunk data,
    /// interpreting and validating it according to the given `pixel` format and
    /// image `palette`.
    ///
    /// Some `pixel` formats imply that `palette` must be `nil`. This
    /// initializer does not check this assumption, as it is expected to have
    /// been verified by ``Palette.init(parsing:pixel:)``.
    /// -   Parameter data:
    ///     The contents of a ``Chunk/bKGD`` chunk to parse.
    /// -   Parameter pixel:
    ///     The pixel format specifying how the chunk data is to be interpreted
    ///     and validated against.
    /// -   Parameter palette:
    ///     The image palette the chunk data is to be validated against, if
    ///     applicable.
    init(parsing data: [UInt8], pixel: PNGFormat.Pixel, palette: PNGPalette?) throws {
        switch pixel {
        case .v1, .v2, .v4, .v8, .v16, .va8, .va16:
            guard data.count == 2 else {
                throw PNGImage.ParsingError.invalidBackgroundChunkLength(data.count, expected: 2)
            }

            let max: UInt16 = .max >> (UInt16.bitWidth - pixel.depth)
            let v: UInt16 = data.load(bigEndian: UInt16.self, as: UInt16.self, at: 0)
            guard v <= max else {
                throw PNGImage.ParsingError.invalidBackgroundSample(v, max: max)
            }
            self.case = .v(v)

        case .rgb8, .rgb16, .rgba8, .rgba16:
            guard data.count == 6 else {
                throw PNGImage.ParsingError.invalidBackgroundChunkLength(data.count, expected: 6)
            }

            let max: UInt16 = .max >> (UInt16.bitWidth - pixel.depth)
            let r: UInt16 = data.load(bigEndian: UInt16.self, as: UInt16.self, at: 0),
                g: UInt16 = data.load(bigEndian: UInt16.self, as: UInt16.self, at: 2),
                b: UInt16 = data.load(bigEndian: UInt16.self, as: UInt16.self, at: 4)
            guard r <= max, g <= max, b <= max else {
                throw PNGImage.ParsingError.invalidBackgroundSample(Swift.max(r, g, b), max: max)
            }
            self.case = .rgb((r, g, b))

        case .indexed1, .indexed2, .indexed4, .indexed8:
            guard let palette else {
                throw PNGImage.DecodingError.required(chunk: .PLTE, before: .bKGD)
            }
            guard data.count == 1 else {
                throw PNGImage.ParsingError.invalidBackgroundChunkLength(data.count, expected: 1)
            }
            let index: Int = .init(data[0])
            guard index < palette.entries.count else {
                throw PNGImage.ParsingError.invalidBackgroundIndex(index, max: palette.entries.count - 1)
            }
            self.case = .palette(index: index)
        }
    }
    /// Encodes this background descriptor as the contents of a
    /// ``Chunk/bKGD`` chunk.
    public
    var serialized:[UInt8]
    {
        switch self.case
        {
        case .palette(index: let i):
            return [.init(i)]
        case .rgb(let c):
            return unsafe .init(unsafeUninitializedCapacity: 6)
            {
                unsafe $0.store(c.r, asBigEndian: UInt16.self, at: 0)
                unsafe $0.store(c.g, asBigEndian: UInt16.self, at: 2)
                unsafe $0.store(c.b, asBigEndian: UInt16.self, at: 4)
                $1 = $0.count
            }
        case .v(let v):
            return unsafe .init(unsafeUninitializedCapacity: 2)
            {
                unsafe $0.store(v, asBigEndian: UInt16.self, at: 0)
                $1 = $0.count
            }
        }
    }
}
