/// An image layout.
///
/// This type stores all the information in an image that is not strictly
/// metadata, or image content.
struct PNGLayout {
    /// The image color format.
    let format: PNGFormat
    /// Indicates if the image uses interlacing or not.
    let interlaced: Bool

    /// Creates an image layout.
    ///
    /// This initializer will validate the fields of the given color
    /// `format`. Passing an invalid `format` will result in a
    /// precondition failure.
    /// -   Parameter format:
    ///     A color format.
    /// -   Parameter interlaced:
    ///     Specifies if the image uses interlacing. The default value is
    ///     `false`.
    init(format: PNGFormat, interlaced: Bool = false) {
        self.format     = format.validate()
        self.interlaced = interlaced
    }
}

extension PNGLayout {
    init?(
        standard: PNGImage.Standard,
        pixel: PNGFormat.Pixel,
        palette: PNGPalette?,
        background: PNGBackground?,
        transparency: PNGTransparency?,
        interlaced: Bool
    ) {
        guard let format: PNGFormat = .recognize(
            standard: standard,
            pixel: pixel,
            palette: palette,
            background: background,
            transparency: transparency
        ) else {
            // if all the inputs have been consistently validated by the parsing
            // APIs, the only error condition is a missing palette for an indexed
            // image. otherwise, it returns `nil` on any input chunk inconsistency
            return nil
        }

        self.init(format: format, interlaced: interlaced)
    }
}
