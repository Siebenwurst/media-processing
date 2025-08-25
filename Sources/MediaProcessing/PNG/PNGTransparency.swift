/// A transparency descriptor.
///
/// This type models the information stored in a ``Chunk/tRNS`` chunk.
/// This information either used to populate the `key` field in
/// an image color ``Format``, or augment its `palette` field, when appropriate.
///
/// The value of this descriptor is stored in the ``PNG.Transparency/case``
/// property, after validation.
struct PNGTransparency {
    /// The value of this transparency descriptor.
    let `case`: Case

    /// A transparency case. This is a separate type for validation purposes.
    enum Case {
        /// A transparency descriptor for an indexed image.
        /// -   Parameter alpha:
        ///     An array of alpha samples, where each sample augments an
        ///     RGB triple in an image ``Palette``. This array can contain no
        ///     more elements than entries in the image palette, but it can
        ///     contain fewer.
        ///
        ///     It is acceptable (though pointless) for the `alpha` array to be
        ///     empty.
        case palette(alpha: [UInt8])
        /// A transparency descriptor for an RGB or BGR image.
        /// -   Parameter key:
        ///     A chroma key used to display transparency. Pixels
        ///     matching this key will be displayed as transparent, if possible.
        ///
        ///     Note that the chroma key components are unscaled samples. If
        ///     the image color depth is less than `16`, only the least-significant
        ///     bits of each sample are inhabited.
        case rgb(key:(r: UInt16, g: UInt16, b: UInt16))
        /// A transparency descriptor for a grayscale image.
        /// -   Parameter key:
        ///     A chroma key used to display transparency. Pixels
        ///     matching this key will be displayed as transparent, if possible.
        ///
        ///     Note that the chroma key is an unscaled sample. If
        ///     the image color depth is less than `16`, only the least-significant
        ///     bits are inhabited.
        case v(key: UInt16)
    }
}

extension PNGTransparency {
    /// Creates a transparency descriptor by parsing the given chunk data,
    /// interpreting and validating it according to the given `pixel` format and
    /// image `palette`.
    ///
    /// Some `pixel` formats imply that `palette` must be `nil`.
    /// This initializer does not check this assumption, as it is expected
    /// to have been verified by ``Palette.init(parsing:pixel:)``.
    /// -   Parameter data:
    ///     The contents of a ``Chunk/tRNS`` chunk to parse.
    /// -   Parameter pixel:
    ///     The pixel format specifying how the chunk data is to be interpreted
    ///     and validated against.
    /// -   Parameter palette:
    ///     The image palette the chunk data is to be validated against, if
    ///     applicable.
    init(parsing data: [UInt8], pixel: PNGFormat.Pixel, palette: PNGPalette?) throws {
        switch pixel {
        case .v1, .v2, .v4, .v8, .v16:
            guard data.count == 2 else {
                throw PNGImage.ParsingError.invalidTransparencyChunkLength(data.count, expected: 2)
            }

            let max: UInt16 = .max >> (UInt16.bitWidth - pixel.depth)
            let v: UInt16 = data.load(bigEndian: UInt16.self, as: UInt16.self, at: 0)
            guard v <= max else {
                throw PNGImage.ParsingError.invalidTransparencySample(v, max: max)
            }
            self.case =  .v(key: v)

        case .rgb8, .rgb16:
            guard data.count == 6 else {
                throw PNGImage.ParsingError.invalidTransparencyChunkLength(data.count, expected: 6)
            }

            let max: UInt16 = .max >> (UInt16.bitWidth - pixel.depth)
            let r: UInt16 = data.load(bigEndian: UInt16.self, as: UInt16.self, at: 0),
                g: UInt16 = data.load(bigEndian: UInt16.self, as: UInt16.self, at: 2),
                b: UInt16 = data.load(bigEndian: UInt16.self, as: UInt16.self, at: 4)
            guard r <= max, g <= max, b <= max else {
                throw PNGImage.ParsingError.invalidTransparencySample(Swift.max(r, g, b), max: max)
            }
            self.case =  .rgb(key: (r, g, b))

        case .indexed1, .indexed2, .indexed4, .indexed8:
            guard let palette else {
                throw PNGImage.DecodingError.required(chunk: .PLTE, before: .tRNS)
            }
            guard data.count <= palette.entries.count else {
                throw PNGImage.ParsingError.invalidTransparencyCount(data.count, max: palette.entries.count)
            }
            self.case =  .palette(alpha: data)

        case .va8, .va16, .rgba8, .rgba16:
            throw PNGImage.ParsingError.unexpectedTransparency(pixel: pixel)
        }
    }
}
