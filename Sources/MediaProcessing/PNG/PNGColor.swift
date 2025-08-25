/// A color target.
///
/// The library provides two built-in color targets, ``PNG.VA`` and ``PNG.RGBA``. A worked
/// example of how to implement a custom color target can be found in the <doc:CustomColor>
/// tutorial.
protocol PNGColor<Aggregate> {
    /// A palette aggregate type.
    ///
    /// This type is the return type of a dereferencing function produced by a
    /// deindexer, and the parameter type of a referencing function produced
    /// by an indexer.
    associatedtype Aggregate

    /// Unpacks an image data storage buffer to an array of this color target,
    /// using a custom deindexing function.
    ///
    /// -   Parameters:
    ///     -   interleaved:
    ///         An image data buffer. It is expected to be obtained from the
    ///         ``PNG/Image/storage`` property of a ``PNG/Image`` image.
    ///     -   format:
    ///         The color format associated with the given data buffer.
    ///         It is expected to be obtained from the the ``PNG/Layout/format`` property of
    ///         a ``PNG/Image`` image.
    ///     -   deindexer:
    ///         A function which uses the palette entries in the color `format` to
    ///         generate a dereferencing function. This function should only be invoked
    ///         if the color `format` is an indexed format.
    ///
    /// See the [indexed color tutorial](Indexing) for more about the semantics of this
    /// function.
    ///
    /// -   Returns:
    ///     A pixel array containing instances of this color target. The pixels
    ///     should appear in the same order as they do in the image data buffer.
    static func unpack(
        _ interleaved: [UInt8],
        of format: PNGFormat,
        deindexer: ([(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]) -> (Int) -> Aggregate
    ) -> [Self]

    /// Unpacks an image data storage buffer to an array of this color target.
    ///
    /// If ``Aggregate`` is `(UInt8, UInt8)`, the default implementation of this
    /// function will use the red and alpha components of the *i*th palette
    /// entry, in that order, as the palette aggregate, given an index *i*,
    /// when unpacking from an indexed color format.
    ///
    /// If ``Aggregate`` is `(UInt8, UInt8, UInt8, UInt8)`, the default
    /// implementation of this function will use the red, green, blue, and
    /// alpha components of the *i*th palette entry, in that order, as the
    /// palette aggregate, given an index *i*.
    ///
    /// See the [indexed color tutorial](Indexing) for more about the semantics of the
    /// default implementations.
    ///
    /// -   Parameters:
    ///     -   interleaved:
    ///         An image data buffer. It is expected to be obtained from the
    ///        ``PNG/Image/storage`` property of a ``PNG/Image``
    ///         image.
    ///     -   format:
    ///         The color format associated with the given data buffer. It is
    ///         expected to be obtained from the the ``PNG/Layout/format`` property of a
    ///         ``PNG/Image`` image.
    /// -   Returns:
    ///     A pixel array containing instances of this color target. The pixels
    ///     should appear in the same order as they do in the image data buffer.
    static func unpack(_ interleaved: [UInt8], of format: PNGFormat) -> [Self]
}

// default-indexer implementations
extension PNGColor<(UInt8, UInt8)> {
    @inlinable
    static func unpack(_ interleaved: [UInt8], of format: PNGFormat) -> [Self] {
        self.unpack(interleaved, of: format) { (palette: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]) in { i in
            (palette[i].r, palette[i].a)
        }}
    }
}

extension PNGColor<(UInt8, UInt8, UInt8, UInt8)> {
    @inlinable
    static func unpack(_ interleaved: [UInt8], of format: PNGFormat) -> [Self] {
        self.unpack(interleaved, of: format) { (palette: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]) in { i in
            palette[i]
        }}
    }
}
