/// The metadata in a PNG image.
struct PNGMetadata {
    /// The image modification time.
    var time: TimeModified?

    /// The image chromaticity.
    var chromaticity: Chromaticity?

    /// The image color profile.
    var colorProfile: ColorProfile?

    /// The image color rendering mode.
    var colorRendering: ColorRendering?

    /// The image gamma.
    var gamma: Gamma?

    /// The frequency histogram of the image palette.
    var histogram: Histogram?

    /// The physical dimensions of the image.
    var physicalDimensions: PhysicalDimensions?

    /// The image color precision.
    var significantBits: SignificantBits?

    /// The suggested palettes of the image.
    var suggestedPalettes: [SuggestedPalette]

    /// The text comments in the image.
    var text: [Text]

    /// An array containing any unparsed application-specific chunks in the image.
    var application: [(type: PNGChunkIdentifier, data: [UInt8])]

    /// Creates a metadata structure.
    ///
    /// -   Parameters:
    ///     -   time:
    ///         An optional modification time.
    ///     -   chromaticity:
    ///         An optional chromaticity descriptor.
    ///     -   colorProfile:
    ///         An optional color profile.
    ///     -   colorRendering:
    ///         An optional color rendering mode.
    ///     -   gamma:
    ///         An optional gamma descriptor.
    ///     -   histogram:
    ///         An optional palette frequency histogram.
    ///     -   physicalDimensions:
    ///         An optional physical dimensions descriptor.
    ///     -   significantBits:
    ///         An optional color precision descriptor.
    ///     -   suggestedPalettes:
    ///         An array of suggested palettes.
    ///     -   text:
    ///         An array of text comments.
    ///     -   application:
    ///         An array of unparsed application-specific chunks.
    ///
    /// This array is allowed to contain public PNG chunks, though it is recommended to use
    /// the library’s strongly-typed interfaces instead for such chunks.
    init(
        time: TimeModified? = nil,
        chromaticity: Chromaticity? = nil,
        colorProfile: ColorProfile? = nil,
        colorRendering: ColorRendering? = nil,
        gamma: Gamma? = nil,
        histogram: Histogram? = nil,
        physicalDimensions: PhysicalDimensions? = nil,
        significantBits: SignificantBits? = nil,
        suggestedPalettes: [SuggestedPalette] = [],
        text: [Text] = [],
        application: [(type: PNGChunkIdentifier, data: [UInt8])] = []
    ) {
        self.time               = time
        self.chromaticity       = chromaticity
        self.colorProfile       = colorProfile
        self.colorRendering     = colorRendering
        self.gamma              = gamma
        self.histogram          = histogram
        self.physicalDimensions = physicalDimensions
        self.significantBits    = significantBits
        self.suggestedPalettes  = suggestedPalettes
        self.text               = text
        self.application        = application
    }
}

extension PNGMetadata {
    static func unique<T>(assign type: PNGChunkIdentifier, to destination:inout T?, parser:() throws -> T) throws {
        guard destination == nil else {
            throw PNGImage.DecodingError.duplicate(chunk: type)
        }
        destination = try parser()
    }

    /// Parses an ancillary chunk, and either adds it to this metadata instance, or stores it
    /// in one of the two `inout` parameters.
    ///
    /// If the given `chunk` is a ``Chunk/bKGD`` or ``Chunk/tRNS`` chunk, it will be stored in
    /// its respective `inout` variable. Otherwise it will be stored within this metadata
    /// instance.
    ///
    /// This function parses and validates the given `chunk` according to the image `pixel`
    /// format and `palette`. It also validates its multiplicity, and its chunk ordering with
    /// respect to the ``Chunk/PLTE`` chunk.
    ///
    /// -   Parameters:
    ///     -   chunk:
    ///         The chunk to process.
    ///
    ///         The `type` identifier of this chunk must not be a critical chunk type.
    ///         (Critical chunk types are ``Chunk/CgBI``, ``Chunk/IHDR``, ``Chunk/PLTE``,
    ///         ``Chunk/IDAT``, and ``Chunk/IEND``.) Passing a critical chunk to this function
    ///         will result in a precondition failure.
    ///
    ///     -   pixel:
    ///         The image pixel format.
    ///
    ///     -   palette:
    ///         The image palette, if available. Client applications are expected to
    ///         set this parameter to `nil` if the ``Chunk/PLTE`` chunk has not
    ///         yet been encountered.
    ///
    ///     -   background:
    ///         The background descriptor, if available. If this function receives
    ///         a ``Chunk/bKGD`` chunk, it will be parsed and stored in this
    ///         variable. Client applications are expected to initialize it to `nil`,
    ///         and should not overwrite it between subsequent calls while processing
    ///         the same image.
    ///
    ///     -   transparency:
    ///         The transparency descriptor, if available. If this function receives
    ///         a ``Chunk/tRNS`` chunk, it will be parsed and stored in this
    ///         variable. Client applications are expected to initialize it to `nil`,
    ///         and should not overwrite it between subsequent calls while processing
    ///         the same image.
    mutating func push(
        ancillary chunk: (type: PNGChunkIdentifier, data: [UInt8]),
        pixel: PNGFormat.Pixel,
        palette: PNGPalette?,
        background: inout PNGBackground?,
        transparency: inout PNGTransparency?
    ) throws {
        switch chunk.type {
        // check before-palette chunk ordering
        case .cHRM, .gAMA, .sRGB, .iCCP, .sBIT:
            guard palette == nil else {
                throw PNGImage.DecodingError.unexpected(chunk: chunk.type, after: .PLTE)
            }
            // check that chunk is not a critical chunk
        case .CgBI, .IHDR, .PLTE, .IDAT, .IEND:
            fatalError("""
                Metadata.push(ancillary:pixel:palette:background:transparency:) \
                cannot be used with critical chunk type '\(chunk.type)'
                """)
        default:
            break
        }

        switch chunk.type {
        case .bKGD:
            try Self.unique(assign: chunk.type, to: &background) {
                try .init(parsing: chunk.data, pixel: pixel, palette: palette)
            }
        case .tRNS:
            try Self.unique(assign: chunk.type, to: &transparency) {
                try .init(parsing: chunk.data, pixel: pixel, palette: palette)
            }

        case .hIST:
            guard let palette else {
                throw PNGImage.DecodingError.required(chunk: .PLTE, before: .hIST)
            }
            try Self.unique(assign: chunk.type, to: &self.histogram) {
                try .init(parsing: chunk.data, palette: palette)
            }

        case .cHRM:
            try Self.unique(assign: chunk.type, to: &self.chromaticity) {
                try .init(parsing: chunk.data)
            }
        case .gAMA:
            try Self.unique(assign: chunk.type, to: &self.gamma) {
                try .init(parsing: chunk.data)
            }
        case .sRGB:
            try Self.unique(assign: chunk.type, to: &self.colorRendering) {
                try .init(parsing: chunk.data)
            }
        case .iCCP:
            try Self.unique(assign: chunk.type, to: &self.colorProfile) {
                try .init(parsing: chunk.data)
            }
        case .sBIT:
            try Self.unique(assign: chunk.type, to: &self.significantBits) {
                try .init(parsing: chunk.data, pixel: pixel)
            }

        case .pHYs:
            try Self.unique(assign: chunk.type, to: &self.physicalDimensions) {
                try .init(parsing: chunk.data)
            }
        case .tIME:
            try Self.unique(assign: chunk.type, to: &self.time) {
                try .init(parsing: chunk.data)
            }

        case .sPLT:
            self.suggestedPalettes.append(try .init(parsing: chunk.data))
        case .iTXt:
            self.text.append(try .init(parsing: chunk.data))
        case .tEXt, .zTXt:
            self.text.append(try .init(parsing: chunk.data, unicode: false))

        default:
            self.application.append(chunk)
        }
    }
}
