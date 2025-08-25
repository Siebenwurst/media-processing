/// An RGBA color target.
///
/// This type is a built-in color target.
struct RGBA<T>: Hashable where T: FixedWidthInteger & UnsignedInteger {
    /// The red component of this color.
    var r: T
    /// The green component of this color.
    var g: T
    /// The blue component of this color.
    var b: T
    /// The alpha component of this color.
    var a: T
}

extension RGBA: Sendable where T: Sendable {}

extension RGBA {
    /// Creates an opaque, monochromatic RGBA color.
    ///
    /// The ``r``, ``g``, and ``b`` components will be set to `value`,
    /// and the ``a`` component will be set to `T.max`.
    ///
    /// -   Parameter value:
    ///     A gray value.
    @inlinable
    init(_ value: T) {
        self.init(value, value, value, T.max)
    }

    /// Creates a monochromatic RGBA color.
    ///
    /// The ``r``, ``g``, and ``b`` components will be set to `value`,
    /// and the ``a`` component will be set to `alpha`.
    /// -   Parameter value:
    ///     A gray value.
    /// -   Parameter alpha:
    ///     An alpha value.
    @inlinable
    init(_ value: T, _ alpha: T) {
        self.init(value, value, value, alpha)
    }

    /// Creates an opaque RGBA color.
    ///
    /// The ``r``, ``g``, and ``b`` components will be set to `red`, `green`,
    /// and `blue`, respectively. The ``a`` component will be set to `T.max`.
    /// -   Parameter red:
    ///     A red value.
    /// -   Parameter green:
    ///     A green value.
    /// -   Parameter blue:
    ///     A blue value.
    @inlinable
    init(_ red: T, _ green: T, _ blue: T) {
        self.init(red, green, blue, T.max)
    }

    /// Creates an RGBA color.
    ///
    /// The ``r``, ``g``, ``b``, and ``a`` components will be set to `red`,
    /// `green`, `blue`, and `alpha` respectively.
    /// -   Parameter red:
    ///     A red value.
    /// -   Parameter green:
    ///     A green value.
    /// -   Parameter blue:
    ///     A blue value.
    /// -   Parameter alpha:
    ///     An alpha value.
    @inlinable
    init(_ red: T, _ green: T, _ blue: T, _ alpha: T) {
        self.r = red
        self.g = green
        self.b = blue
        self.a = alpha
    }
}

extension RGBA: PNGColor {
    /// Palette aggregates are (*red*, *green*, *blue*, *alpha*) quadruplets.
    typealias Aggregate = (UInt8, UInt8, UInt8, UInt8)

    /// Unpacks an image data storage buffer to an array of RGBA pixels.
    ///
    /// For a grayscale color `format`, this function expands
    /// pixels of the form (*v*) to RGBA quadruplets (*v*, *v*, *v*, `T.max`).
    ///
    /// For a grayscale-alpha color `format`, this function expands
    /// pixels of the form (*v*, *a*) to RGBA quadruplets (*v*, *v*, *v*, *a*).
    ///
    /// For an RGB color `format`, this function expands
    /// pixels of the form (*r*, *g*, *b*) to RGBA quadruplets (*r*, *g*, *b*, `T.max`).
    ///
    /// For a BGR color `format`, this function expands
    /// pixels of the form (*b*, *g*, *r*) to RGBA quadruplets (*r*, *g*, *b*, `T.max`).
    ///
    /// For a BGRA color `format`, this function shuffles
    /// pixels of the form (*b*, *g*, *r*, *a*) into RGBA quadruplets (*r*, *g*, *b*, *a*).
    ///
    /// This function will apply chroma keys if present. The unpacked components
    /// are scaled to fill the range of `T`, according to the color depth
    /// computed from the color `format`.
    /// -   Parameter interleaved:
    ///     An image data buffer. It is expected to be obtained from the
    ///     ``Image/storage`` property of a ``Image``
    ///     image.
    /// -   Parameter format:
    ///     The color format associated with the given data buffer.
    ///     It is expected to be obtained from the the `layout.format` property of a
    ///     ``Image`` image.
    /// -   Parameter deindexer:
    ///     A function which uses the palette entries in the color `format` to
    ///     generate a dereferencing function. This function is only invoked
    ///     if the color `format` is an indexed format. Its palette aggregates
    ///     will be interpreted as (*red*, *green*, *blue*, *alpha*) quadruplets.
    ///
    /// See the [indexed color tutorial](https://github.com/tayloraswift/swift-png/tree/master/examples#using-indexed-images)
    /// for more about the semantics of this function.
    /// -   Returns:
    ///     An array of RGBA pixels. The pixels
    ///     appear in the same order as they do in the image data buffer.
    @_specialize(where T == UInt8)
    @_specialize(where T == UInt16)
    @_specialize(where T == UInt32)
    @_specialize(where T == UInt64)
    @_specialize(where T == UInt)
    static func unpack(
        _ interleaved: [UInt8],
        of format: PNGFormat,
        deindexer: ([(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]) -> (Int) -> Aggregate
    ) -> [Self] {
        let depth: Int = format.pixel.depth
        switch format {
        case .indexed1(palette: let palette, fill: _),
            .indexed2(palette: let palette, fill: _),
            .indexed4(palette: let palette, fill: _),
            .indexed8(palette: let palette, fill: _):
            return convolve(
                interleaved,
                dereference: deindexer(palette)
            ) { (c: (T, T, T, T)) in
                .init(c.0, c.1, c.2, c.3)
            }

        case .v1(fill: _, key: nil),
            .v2(fill: _, key: nil),
            .v4(fill: _, key: nil),
            .v8(fill: _, key: nil):
            return convolve(interleaved, of: UInt8.self, depth: depth) { (c: T, _) in .init(c) }
        case    .v16(fill: _, key: nil):
            return convolve(interleaved, of: UInt16.self, depth: depth) { (c: T, _) in .init(c) }
        case .v1(fill: _, key: let key?),
            .v2(fill: _, key: let key?),
            .v4(fill: _, key: let key?),
            .v8(fill: _, key: let key?):
            return convolve(interleaved, of: UInt8.self, depth: depth) { (c: T, k: UInt8 ) in
                .init(c, k == key ? .min : .max)
            }
        case .v16(fill: _, key: let key?):
            return convolve(interleaved, of: UInt16.self, depth: depth) { (c: T, k: UInt16) in
                .init(c, k == key ? .min : .max)
            }

        case .va8(fill: _):
            return convolve(interleaved, of: UInt8.self, depth: depth) { (c: (T, T)) in .init(c.0, c.1) }
        case .va16(fill: _):
            return convolve(interleaved, of: UInt16.self, depth: depth) { (c:(T, T)) in .init(c.0, c.1) }

        case .bgr8(palette: _, fill: _, key: nil):
            return convolve(interleaved, of: UInt8.self, depth: depth) { (c: (T, T, T), _) in .init(c.2, c.1, c.0) }
        case .bgr8(palette: _, fill: _, key: let key?):
            return convolve(interleaved, of: UInt8.self, depth: depth) { (c: (T, T, T), k: (UInt8,  UInt8,  UInt8)) in
                .init(c.2, c.1, c.0, k == key ? .min : .max)
            }

        case .rgb8(palette: _, fill: _, key: nil):
            return convolve(interleaved, of: UInt8.self, depth: depth) { (c: (T, T, T), _) in .init(c.0, c.1, c.2) }
        case .rgb16(palette: _, fill: _, key: nil):
            return convolve(interleaved, of: UInt16.self, depth: depth) { (c: (T, T, T), _) in .init(c.0, c.1, c.2) }
        case .rgb8(palette: _, fill: _, key: let key?):
            return convolve(interleaved, of: UInt8.self, depth: depth) { (c: (T, T, T), k: (UInt8, UInt8, UInt8)) in
                .init(c.0, c.1, c.2, k == key ? .min : .max)
            }
        case .rgb16(palette: _, fill: _, key: let key?):
            return convolve(interleaved, of: UInt16.self, depth: depth) { (c: (T, T, T), k: (UInt16, UInt16, UInt16)) in
                .init(c.0, c.1, c.2, k == key ? .min : .max)
            }

        case .bgra8(palette: _, fill: _):
            return convolve(interleaved, of: UInt8.self, depth: depth) { (c:(T, T, T, T)) in .init(c.2, c.1, c.0, c.3) }

        case .rgba8(palette: _, fill: _):
            return convolve(interleaved, of: UInt8.self, depth: depth) { (c: (T, T, T, T)) in .init(c.0, c.1, c.2, c.3) }
        case .rgba16(palette: _, fill: _):
            return convolve(interleaved, of: UInt16.self, depth: depth) {
                (c:(T, T, T, T)) in .init(c.0, c.1, c.2, c.3)
            }
        }
    }
}
