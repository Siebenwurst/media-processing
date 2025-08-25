import _Hashing

struct PNGImage {
    static let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    /// The size of this image, measured in pixels.
    let size:(x:Int, y:Int)
    /// The layout of this image.
    let layout: PNGLayout
    /// The metadata in this image.
    var metadata: PNGMetadata
    /// The raw backing storage of the image content.
    ///
    /// Depending on the bit depth of the image, it either stores a matrix
    /// of ``UInt8`` samples, or a matrix of big-endian ``UInt16``
    /// samples. The pixels are arranged in row-major order, where the
    /// beginning of the storage array corresponds to the visual top-left
    /// corner of the image, regardless of whether the ``layout`` is
    /// ``Layout/interlaced`` or not.
    private(set) var storage: [UInt8]

    /// A PNG standard.
    enum Standard {
        /// The core PNG color formats.
        case common
        /// The iPhone-optimized PNG color formats.
        case ios
    }

    /// Decompresses and decodes a PNG from the given bytestream.
    ///
    /// On appropriate platforms, the ``decompress(path:)`` function provides
    /// a file system-aware interface to this function.
    /// -   Parameter stream:
    ///     A bytestream providing the contents of a PNG file.
    /// -   Returns:
    ///     The decoded image.
    static func decode<ByteStream: AsyncSequence>(from stream: ByteStream) async throws -> PNGImage where ByteStream.Element == UInt8 {
        var iterator = stream.makeAsyncIterator()
        try await iterator.signature()
        let (standard, header): (Standard, Header) = try await {
            var chunk: (type: PNGChunkIdentifier, data: [UInt8]) = try await iterator.chunk()
            let standard: Standard
            switch chunk.type {
            case .CgBI:
                standard    = .ios
                chunk       = try await iterator.chunk()
            default:
                standard    = .common
            }
            switch chunk.type {
            case .IHDR:
                return (standard, try .init(parsing: chunk.data, standard: standard))
            case let type:
                throw DecodingError.required(chunk: .IHDR, before: type)
            }
        }()

        var chunk: (type: PNGChunkIdentifier, data: [UInt8]) = try await iterator.chunk()

        var context: PNGContext = try await {
            var palette: PNGPalette?
            var background: PNGBackground?,
                transparency: PNGTransparency?
            var metadata: PNGMetadata = .init()
            while true {
                switch chunk.type {
                case .IHDR:
                    throw DecodingError.duplicate(chunk: .IHDR)

                case .PLTE:
                    guard palette == nil else {
                        throw DecodingError.duplicate(chunk: .PLTE)
                    }
                    guard background == nil else {
                        throw DecodingError.unexpected(chunk: .PLTE, after: .bKGD)
                    }
                    guard transparency == nil else {
                        throw DecodingError.unexpected(chunk: .PLTE, after: .tRNS)
                    }

                    palette = try .init(parsing: chunk.data, pixel: header.pixel)

                case .IDAT:
                    guard let context = PNGContext(
                        standard: standard,
                        header: header,
                        palette: palette,
                        background: background,
                        transparency: transparency,
                        metadata: metadata
                    ) else {
                        throw DecodingError.required(chunk: .PLTE, before: .IDAT)
                    }
                    return context

                case .IEND:
                    throw DecodingError.required(chunk: .IDAT, before: .IEND)

                default:
                    try metadata.push(ancillary: chunk, pixel: header.pixel,
                                      palette:        palette,
                                      background:     &background,
                                      transparency:   &transparency)
                }

                chunk = try await iterator.chunk()
            }
        }()

        while chunk.type == .IDAT {
            try context.push(data: chunk.data)
            chunk = try await iterator.chunk()
        }

        while true {
            try context.push(ancillary: chunk)
            guard chunk.type != .IEND
            else
            {
                return context.image
            }
            chunk = try await iterator.chunk()
        }
    }

    enum LexingError: Error {
        /// The lexer encountered end-of-stream while reading signature
        /// bytes from a bytestream.
        case truncatedSignature
        /// The signature bytes read by the lexer did not match the expected
        /// sequence.
        ///
        /// The expected byte sequence is `[137, 80, 78, 71, 13, 10, 26, 10]`.
        /// -   Parameter _:
        ///     The invalid signature bytes.
        case invalidSignature([UInt8])
        /// The lexer encountered end-of-stream while reading a chunk header
        /// from a bytestream.
        case truncatedChunkHeader
        /// The lexer encountered end-of-stream while reading a chunk body
        /// from a bytestream.
        /// -   Parameter expected:
        ///     The number of bytes the lexer expected to read.
        case truncatedChunkBody(expected:Int)
        /// The lexer read a chunk with an invalid type identifier code.
        /// -   Parameter _:
        ///     The invalid type identifier code.
        case invalidChunkTypeCode(UInt32)
        /// The chunk checksum computed by the lexer did not match the
        /// checksum declared in the chunk footer.
        /// -   Parameter declared:
        ///     The checksum declared in the chunk footer.
        /// -   Parameter computed:
        ///     The checksum computed by the lexer.
        case invalidChunkChecksum(declared:UInt32, computed:UInt32)
    }
}

private extension AsyncIteratorProtocol where Element == UInt8 {

    /// Lexes the eight PNG signature bytes from this bytestream.
    ///
    /// This function expects to read the byte sequence
    /// `[137, 80, 78, 71, 13, 10, 26, 10]`. It reports end-of-stream by throwing
    /// ``PNG/LexingError.truncatedSignature``. To recover on end-of-stream,
    /// catch this error case.
    ///
    /// This function is the inverse of ``PNG.BytestreamDestination.signature()``.
    mutating func signature() async throws {
        guard let bytes: [UInt8] = try await self.read(count: PNGImage.signature.count) else {
            throw PNGImage.LexingError.truncatedSignature
        }
        guard bytes == PNGImage.signature else {
            throw PNGImage.LexingError.invalidSignature(bytes)
        }
    }

    /// Lexes a chunk from this bytestream.
    ///
    /// This function reads a chunk, validating its stored checksum for
    /// data integrity. It reports end-of-stream by throwing
    /// ``PNG/LexingError.truncatedChunkHeader`` or
    /// ``PNG/LexingError.truncatedChunkBody(expected:)``. To recover on end-of-stream,
    /// catch these two error cases.
    ///
    /// This function is the inverse of ``PNG.BytestreamDestination.format(type:data:)``.
    /// -   Returns:
    ///     The type identifier, and contents of the lexed chunk. The chunk
    ///     contents do not include the checksum footer.
    mutating func chunk() async throws -> (type: PNGChunkIdentifier, data: [UInt8]) {
        guard let header: [UInt8] = try await self.read(count: 8) else {
            throw PNGImage.LexingError.truncatedChunkHeader
        }

        let length: Int  = header.prefix(4).load(bigEndian: UInt32.self, as:  Int.self),
            name: UInt32 = header.suffix(4).load(bigEndian: UInt32.self, as: UInt32.self)

        guard let type = PNGChunkIdentifier(validating: name) else {
            throw PNGImage.LexingError.invalidChunkTypeCode(name)
        }
        let bytes:Int = length + MemoryLayout<UInt32>.size
        guard var data: [UInt8] = try await self.read(count: bytes) else {
            throw PNGImage.LexingError.truncatedChunkBody(expected: bytes)
        }

        let declared: CRC32 = .init(checksum: data.suffix(4).load(bigEndian: UInt32.self, as: UInt32.self))
        data.removeLast(4)
        let computed: CRC32 = .init(hashing: header.suffix(4)).updated(with: data)

        guard declared == computed else {
            throw PNGImage.LexingError.invalidChunkChecksum(
                declared: declared.checksum,
                computed: computed.checksum)
        }

        return (type, data)
    }

    private mutating func read(count: Int) async throws -> [UInt8]? {
        var chunk: [UInt8]? = nil
        while (chunk?.count ?? 0) < count {
            guard let byte = try await next() else { return chunk }
            if chunk == nil { chunk = [] }
            chunk!.append(byte)
        }
        return chunk
    }
}

extension PNGImage {
    /// An image header.
    ///
    /// This type models the information stored in a ``Chunk/IHDR`` chunk.
    struct Header {
        /// The size of an image, measured in pixels.
        let size: (x: Int, y: Int)
        /// The pixel format of an image.
        let pixel: PNGFormat.Pixel
        /// Indicates whether an image uses interlacing.
        let interlaced: Bool

        /// Creates an image header by parsing the given chunk data, interpreting it
        /// according to the given PNG `standard`.
        /// -   Parameter data:
        ///     The contents of an ``Chunk/IHDR`` chunk to parse.
        /// -   Parameter standard:
        ///     Specifies if the header should be interpreted as a standard PNG header,
        ///     or an iphone-optimized PNG header.
        init(parsing data: [UInt8], standard: Standard) throws {
            guard data.count == 13 else {
                throw ParsingError.invalidHeaderChunkLength(data.count)
            }

            guard let pixel: PNGFormat.Pixel = .recognize(code: (data[8], data[9])) else
            {
                throw ParsingError.invalidHeaderPixelFormatCode((data[8], data[9]))
            }

            // iphone-optimized PNG can only have pixel type rgb8 or rgb16
            switch (standard, pixel) {
            case (.common, _):
                break
            case (.ios, .rgb8), (.ios, .rgba8):
                break
            default:
                throw ParsingError.invalidHeaderPixelFormat(pixel, standard: standard)
            }

            self.pixel = pixel

            // validate other fields
            guard data[10] == 0 else {
                throw ParsingError.invalidHeaderCompressionMethodCode(data[10])
            }
            guard data[11] == 0 else {
                throw ParsingError.invalidHeaderFilterCode(data[11])
            }

            switch data[12]
            {
            case 0:
                self.interlaced = false
            case 1:
                self.interlaced = true
            case let code:
                throw ParsingError.invalidHeaderInterlacingCode(code)
            }

            self.size.x = data.load(bigEndian: UInt32.self, as: Int.self, at: 0)
            self.size.y = data.load(bigEndian: UInt32.self, as: Int.self, at: 4)
            // validate size
            guard self.size.x > 0, self.size.y > 0
            else
            {
                throw ParsingError.invalidHeaderSize(self.size)
            }
        }
    }
}

extension PNGImage {
    /// A decoding error.
    enum DecodingError: Error {
        /// The decoder encountered a chunk of a type that requires a
        /// previously encountered chunk of a particular type.
        /// -   Parameter chunk:
        ///     The type of the preceeding chunk required by the encountered chunk.
        /// -   Parameter before:
        ///     The type of the encountered chunk.

        ///     The decoder encountered multiple instances of a chunk type that
        ///     can only appear once in a PNG file.
        /// -   Parameter chunk:
        ///     The type of the duplicated chunk.

        ///     The decoder encountered a chunk of a type that is not allowed
        ///     to appear after a previously encountered chunk of a particular type.
        ///
        ///     If both fields are set to ``Chunk/IDAT``, this indicates
        ///     a non-contiguous ``Chunk/IDAT`` sequence.
        /// -   Parameter chunk:
        ///     The type of the encountered chunk.
        /// -   Parameter after:
        ///     The type of the preceeding chunk that precludes the encountered chunk.
        case required(chunk: PNGChunkIdentifier, before: PNGChunkIdentifier)
        case duplicate(chunk: PNGChunkIdentifier)
        case unexpected(chunk: PNGChunkIdentifier, after: PNGChunkIdentifier)

        /// The decoder finished processing the last ``Chunk/IDAT`` chunk
        /// before the compressed image data stream was properly terminated.
        case incompleteImageDataCompressedDatastream
        /// The decoder encountered additional ``Chunk/IDAT`` chunks
        /// after the end of the compressed image data stream.
        ///
        /// This error should not be confused with an ``unexpected(chunk:after:)``
        /// error with both fields set to ``Chunk/IDAT``, which indicates a
        /// non-contiguous ``Chunk/IDAT`` sequence.
        case extraneousImageDataCompressedData
        /// The compressed image data stream produces more uncompressed image
        /// data than expected.
        case extraneousImageData
    }

    /// A parsing error.
    enum ParsingError: Error {
        /// An ``Chunk/IHDR`` chunk had the wrong length.
        ///
        /// Header chunks should be exactly `13` bytes long.
        /// -   Parameter _:
        ///     The chunk length.
        case invalidHeaderChunkLength(Int)

        /// An ``Chunk/IHDR`` chunk had an invalid pixel format code.
        /// -   Parameter _:
        ///     The invalid pixel format code.
        case invalidHeaderPixelFormatCode((UInt8, UInt8))

        /// An ``Chunk/IHDR`` chunk specified a pixel format that is disallowed
        /// according to the PNG standard used by the image.
        ///
        /// This error gets thrown when an iphone-optimized image
        /// (``Standard/ios``) has a pixel format that is not
        /// ``Format.Pixel/rgb8`` or ``Format.Pixel/rgba8``.
        /// -   Parameter _:
        ///     The invalid pixel format.
        /// -   Parameter standard:
        ///     The PNG standard. This error is only relevant for iphone-optimized
        ///     images, so library-generated instances of this error case always have
        ///     this field set to ``Standard/ios``.
        case invalidHeaderPixelFormat(PNGFormat.Pixel, standard: Standard)

        /// An ``Chunk/IHDR`` chunk had an invalid compression method code.
        ///
        /// The compression method code should always be `0`.
        /// -   Parameter _:
        ///     The invalid compression method code.
        case invalidHeaderCompressionMethodCode(UInt8)

        /// An ``Chunk/IHDR`` chunk had an invalid filter code.
        ///
        /// The filter code should always be `0`.
        /// -   Parameter _:
        ///     The invalid filter code.
        case invalidHeaderFilterCode(UInt8)

        /// An ``Chunk/IHDR`` chunk had an invalid interlacing code.
        ///
        /// The interlacing code should be either `0` or `1`.
        /// -   Parameter _:
        ///     The invalid interlacing code.
        case invalidHeaderInterlacingCode(UInt8)

        /// An ``Chunk/IHDR`` chunk specified an invalid image size.
        ///
        /// Both size dimensions must be strictly positive.
        /// -   Parameter _:
        ///     The invalid size.
        case invalidHeaderSize((x:Int, y:Int))


        /// The parser encountered a ``Chunk/PLTE`` chunk in an image
        /// with a pixel format that forbids it.
        /// -   Parameter pixel:
        ///     The image pixel format.
        case unexpectedPalette(pixel: PNGFormat.Pixel)

        /// A ``Chunk/PLTE`` chunk had a length that is not divisible by `3`.
        /// -   Parameter _:
        ///     The chunk length.
        case invalidPaletteChunkLength(Int)

        /// A ``Chunk/PLTE`` chunk contained more entries than allowed.
        /// -   Parameter _:
        ///     The number of palette entries.
        /// -   Parameter max:
        ///     The maximum allowed number of palette entries, according to the
        ///     image bit depth.
        case invalidPaletteCount(Int, max: Int)

        /// The parser encountered a ``Chunk/tRNS`` chunk in an image
        /// with a pixel format that forbids it.
        /// -   Parameter pixel:
        ///     The image pixel format.
        case unexpectedTransparency(pixel: PNGFormat.Pixel)

        /// A ``Chunk/tRNS`` chunk had the wrong length.
        /// -   Parameter _:
        ///     The chunk length.
        /// -   Parameter expected:
        ///     The expected chunk length.
        case invalidTransparencyChunkLength(Int, expected: Int)

        /// A ``Chunk/tRNS`` chunk contained an invalid chroma key sample.
        /// -   Parameter _:
        ///     The value of the invalid chroma key sample.
        /// -   Parameter max:
        ///     The maximum allowed value for a chroma key sample, according to the
        ///     image color depth.
        case invalidTransparencySample(UInt16, max: UInt16)

        /// A ``Chunk/tRNS`` chunk contained too many alpha samples.
        /// -   Parameter _:
        ///     The number of alpha samples present.
        /// -   Parameter max:
        ///     The maximum allowed number of alpha samples, which is equal to
        ///     the number of entries in the image palette.
        case invalidTransparencyCount(Int, max: Int)


        /// A ``Chunk/bKGD`` chunk had the wrong length.
        /// -   Parameter _:
        ///     The chunk length.
        /// -   Parameter expected:
        ///     The expected chunk length.
        case invalidBackgroundChunkLength(Int, expected: Int)

        /// A ``Chunk/bKGD`` chunk contained an invalid background sample.
        /// -   Parameter _:
        ///     The value of the invalid background sample.
        /// -   Parameter max:
        ///     The maximum allowed value for a background sample, according to the
        ///     image color depth.
        case invalidBackgroundSample(UInt16, max: UInt16)

        /// A ``Chunk/bKGD`` chunk specified an out-of-range palette index.
        /// -   Parameter _:
        ///     The invalid index.
        /// -   Parameter max:
        ///     The maximum allowed index value, which is equal to one less than
        ///     the number of entries in the image palette.
        case invalidBackgroundIndex(Int, max: Int)

        /// A ``Chunk/hIST`` chunk had the wrong length.
        /// -   Parameter _:
        ///     The chunk length.
        /// -   Parameter expected:
        ///     The expected chunk length.
        case invalidHistogramChunkLength(Int, expected: Int)

        /// A ``Chunk/gAMA`` chunk had the wrong length.
        ///
        /// Gamma chunks should be exactly `4` bytes long.
        /// -   Parameter _:
        ///     The chunk length.
        case invalidGammaChunkLength(Int)

        /// A ``Chunk/cHRM`` chunk had the wrong length.
        ///
        /// Chromaticity chunks should be exactly `32` bytes long.
        /// -   Parameter _:
        ///     The chunk length.
        case invalidChromaticityChunkLength(Int)

        /// An ``Chunk/sRGB`` chunk had the wrong length.
        ///
        /// Color rendering chunks should be exactly `1` byte long.
        /// -   Parameter _:
        ///     The chunk length.
        case invalidColorRenderingChunkLength(Int)

        /// An ``Chunk/sRGB`` chunk had an invalid color rendering code.
        ///
        /// The color rendering code should be one of `0`, `1`, `2`, or `3`.
        /// -   Parameter _:
        ///     The invalid color rendering code.
        case invalidColorRenderingCode(UInt8)

        /// An ``Chunk/sBIT`` chunk had the wrong length.
        /// -   Parameter _:
        ///     The chunk length.
        /// -   Parameter expected:
        ///     The expected chunk length.
        case invalidSignificantBitsChunkLength(Int, expected: Int)

        /// An ``Chunk/sBIT`` chunk specified an invalid precision value.
        /// -   Parameter _:
        ///     The invalid precision value.
        /// -   Parameter max:
        ///     The maximum allowed precision value, which is equal to the image
        ///     color depth.
        case invalidSignificantBitsPrecision(Int, max: Int)

        /// An ``Chunk/iCCP`` chunk had an invalid length.
        /// -   Parameter _:
        ///     The chunk length.
        /// -   Parameter min:
        ///     The minimum expected chunk length.
        case invalidColorProfileChunkLength(Int, min: Int)

        /// An ``Chunk/iCCP`` chunk had an invalid profile name.
        /// -   Parameter _:
        ///     The invalid profile name, or `nil` if the parser could not find
        ///     the null-terminator of the profile name string.
        case invalidColorProfileName(String?)

        /// An ``Chunk/iCCP`` chunk had an invalid compression method code.
        ///
        /// The compression method code should always be `0`.
        /// -   Parameter _:
        ///     The invalid compression method code.
        case invalidColorProfileCompressionMethodCode(UInt8)

        /// The compressed data stream in an ``Chunk/iCCP`` chunk was not
        /// properly terminated.
        case incompleteColorProfileCompressedDatastream

        /// A ``Chunk/pHYs`` chunk had the wrong length.
        ///
        /// Physical dimensions chunks should be exactly `9` bytes long.
        /// -   Parameter _:
        ///     The chunk length.
        case invalidPhysicalDimensionsChunkLength(Int)

        /// A ``Chunk/pHYs`` chunk had an invalid density unit code.
        ///
        /// The density code should be either `0` or `1`.
        /// -   Parameter _:
        ///     The invalid density unit code.
        case invalidPhysicalDimensionsDensityUnitCode(UInt8)

        /// An ``Chunk/sPLT`` chunk had an invalid length.
        /// -   Parameter _:
        ///     The chunk length.
        /// -   Parameter min:
        ///     The minimum expected chunk length.
        case invalidSuggestedPaletteChunkLength(Int, min: Int)

        /// An ``Chunk/sPLT`` chunk had an invalid palette name.
        /// -   Parameter _:
        ///     The invalid palette name, or `nil` if the parser could not find
        ///     the null-terminator of the palette name string.
        case invalidSuggestedPaletteName(String?)

        /// The length of the palette data in an ``Chunk/sPLT`` chunk was
        /// not divisible by its expected stride.
        /// -   Parameter _:
        ///     The length of the palette data.
        /// -   Parameter stride:
        ///     The expected stride of the palette entries.
        case invalidSuggestedPaletteDataLength(Int, stride: Int)

        /// An ``Chunk/sPLT`` chunk had an invalid depth code.
        ///
        /// The depth code should be either `8` or `16`.
        /// -   Parameter _:
        ///     The invalid depth code.
        case invalidSuggestedPaletteDepthCode(UInt8)

        /// The entries in an ``Chunk/sPLT`` chunk were not ordered by
        /// descending frequency.
        case invalidSuggestedPaletteFrequency

        /// A ``Chunk/tIME`` chunk had the wrong length.
        ///
        /// Time modified chunks should be exactly `7` bytes long.
        /// -   Parameter _:
        ///     The chunk length.
        case invalidTimeModifiedChunkLength(Int)

        /// A ``Chunk/tIME`` chunk specified an invalid timestamp.
        /// -   Parameter year:
        ///     The specified year.
        /// -   Parameter month:
        ///     The specified month.
        /// -   Parameter day:
        ///     The specified day.
        /// -   Parameter hour:
        ///     The specified hour.
        /// -   Parameter minute:
        ///     The specified minute.
        /// -   Parameter second:
        ///     The specified second.
        case invalidTimeModifiedTime(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int)

        /// A ``Chunk/tEXt``, ``Chunk/zTXt``, or ``Chunk/iTXt`` chunk
        /// had an invalid english keyword.
        /// -   Parameter _:
        ///     The invalid english keyword, or `nil` if the parser could not find
        ///     the null-terminator of the keyword string.
        case invalidTextEnglishKeyword(String?)

        /// A ``Chunk/tEXt``, ``Chunk/zTXt``, or ``Chunk/iTXt`` chunk
        /// had an invalid length.
        /// -   Parameter _:
        ///     The chunk length.
        /// -   Parameter min:
        ///     The minimum expected chunk length.
        case invalidTextChunkLength(Int, min: Int)

        /// An ``Chunk/iTXt`` chunk had an invalid compression code.
        ///
        /// The compression code should be either `0` or `1`.
        /// -   Parameter _:
        ///     The invalid compression code.
        case invalidTextCompressionCode(UInt8)

        /// A ``Chunk/zTXt`` or ``Chunk/iTXt`` chunk had an invalid
        /// compression method code.
        ///
        /// The compression method code should always be `0`.
        /// -   Parameter _:
        ///     The invalid compression method code.
        case invalidTextCompressionMethodCode(UInt8)

        /// An ``Chunk/iTXt`` chunk had an invalid language tag.
        /// -   Parameter _:
        ///     The invalid language tag component, or `nil` if the parser could
        ///     not find the null-terminator of the language tag string.
        ///     The language tag component is not the entire language tag string.
        case invalidTextLanguageTag(String?)

        /// The parser could not find the null-terminator of the localized
        /// keyword string in an ``Chunk/iTXt`` chunk.
        case invalidTextLocalizedKeyword

        /// The compressed data stream in a ``Chunk/zTXt`` or ``Chunk/iTXt``
        /// chunk was not properly terminated.
        case incompleteTextCompressedDatastream
    }
}

extension Array where Element == UInt8 {
    func load<T, U>(bigEndian: T.Type, as type: U.Type, at byte: Int) -> U where T: FixedWidthInteger, U: BinaryInteger {
        return self[byte ..< byte + MemoryLayout<T>.size].load(bigEndian: T.self, as: U.self)
    }
}

extension UnsafeMutableBufferPointer where Element == UInt8 {
    func store<U, T>(_ value: U, asBigEndian type: T.Type, at byte: Int = 0) where U: BinaryInteger, T: FixedWidthInteger {
        let cast: T = .init(truncatingIfNeeded: value)
        unsafe Swift.withUnsafeBytes(of: cast.bigEndian) {
            guard let source: UnsafeRawPointer = $0.baseAddress, let destination:UnsafeMutableRawPointer = unsafe self.baseAddress.map(UnsafeMutableRawPointer.init(_:)) else {
                return
            }

            unsafe (destination + byte).copyMemory(from: source, byteCount: MemoryLayout<T>.size)
        }
    }
}

extension PNGImage {
    init?(
        standard: Standard,
        header: Header,
        palette: PNGPalette?,
        background: PNGBackground?,
        transparency: PNGTransparency?,
        metadata: PNGMetadata,
        uninitialized: Bool
    ) {
        guard let layout = PNGLayout(
                standard: standard,
                pixel: header.pixel,
                palette: palette,
                background: background,
                transparency: transparency,
                interlaced: header.interlaced)
        else {
            return nil
        }

        self.size = header.size
        self.layout = layout
        self.metadata = metadata

        let count: Int = header.size.x * header.size.y,
            bytes: Int = count * (layout.format.pixel.volume + 7) >> 3
        if uninitialized {
            self.storage = unsafe .init(unsafeUninitializedCapacity: bytes) {
                $1 = bytes
            }
        } else {
            self.storage = .init(repeating: 0, count: bytes)
        }
    }

    mutating func assign<C>(scanline: C, at base: (x: Int, y: Int), stride: Int) where C: RandomAccessCollection, C.Index == Int, C.Element == UInt8 {
        let indices: EnumeratedSequence<StrideTo<Int>> = Swift.stride(from: base.x, to: self.size.x, by: stride).enumerated()
        switch self.layout.format {
        // 0 x 1
        case .v1, .indexed1:
            for (i, x) in indices {
                let a = i >> 3 &+ scanline.startIndex,
                    b = ~i & 0b111
                self.storage[base.y &* self.size.x &+ x] = scanline[a] &>> b & 0b0001
            }

        case .v2, .indexed2:
            for (i, x) in indices {
                let a = i >> 2 &+ scanline.startIndex,
                    b = (~i & 0b011) << 1
                self.storage[base.y &* self.size.x &+ x] = scanline[a] &>> b & 0b0011
            }

        case .v4, .indexed4:
            for (i, x) in indices {
                let a = i >> 1 &+ scanline.startIndex,
                    b = (~i & 0b001) << 2
                self.storage[base.y &* self.size.x &+ x] = scanline[a] &>> b & 0b1111
            }

        // 1 x 1
        case .v8, .indexed8:
            for (i, x) in indices {
                let a = i &+ scanline.startIndex,
                    d = base.y &* self.size.x &+ x
                self.storage[d] = scanline[a]
            }
        // 1 x 2, 2 x 1
        case .va8, .v16:
            for (i, x) in indices {
                let a = 2 &* i &+ scanline.startIndex,
                    d = 2 &* (base.y &* self.size.x &+ x)
                self.storage[d] = scanline[a]
                self.storage[d &+ 1] = scanline[a &+ 1]
            }
        // 1 x 3
        case .rgb8, .bgr8:
            for (i, x) in indices {
                let a = 3 &* i &+ scanline.startIndex,
                    d = 3 &* (base.y &* self.size.x &+ x)
                self.storage[d] = scanline[a]
                self.storage[d &+ 1] = scanline[a &+ 1]
                self.storage[d &+ 2] = scanline[a &+ 2]
            }
        // 1 x 4, 2 x 2
        case .rgba8, .bgra8, .va16:
            for (i, x) in indices {
                let a = 4 &* i &+ scanline.startIndex,
                    d = 4 &* (base.y &* self.size.x &+ x)
                self.storage[d] = scanline[a]
                self.storage[d &+ 1] = scanline[a &+ 1]
                self.storage[d &+ 2] = scanline[a &+ 2]
                self.storage[d &+ 3] = scanline[a &+ 3]
            }
        // 2 x 3
        case .rgb16:
            for (i, x) in indices {
                let a = 6 &* i &+ scanline.startIndex,
                    d = 6 &* (base.y &* self.size.x &+ x)
                self.storage[d] = scanline[a]
                self.storage[d &+ 1] = scanline[a &+ 1]
                self.storage[d &+ 2] = scanline[a &+ 2]
                self.storage[d &+ 3] = scanline[a &+ 3]
                self.storage[d &+ 4] = scanline[a &+ 4]
                self.storage[d &+ 5] = scanline[a &+ 5]
            }
        // 2 x 4
        case .rgba16:
            for (i, x) in indices {
                let a = 8 &* i &+ scanline.startIndex,
                    d = 8 &* (base.y &* self.size.x &+ x)
                self.storage[d] = scanline[a]
                self.storage[d &+ 1] = scanline[a &+ 1]
                self.storage[d &+ 2] = scanline[a &+ 2]
                self.storage[d &+ 3] = scanline[a &+ 3]
                self.storage[d &+ 4] = scanline[a &+ 4]
                self.storage[d &+ 5] = scanline[a &+ 5]
                self.storage[d &+ 6] = scanline[a &+ 6]
                self.storage[d &+ 7] = scanline[a &+ 7]
            }
        }
    }

    mutating func overdraw(at base: (x: Int, y: Int), brush: (x: Int, y: Int)) {
        guard brush.x * brush.y > 1 else {
            return
        }

        switch self.layout.format {
        // 1-byte stride
        case .v1, .v2, .v4, .v8, .indexed1, .indexed2, .indexed4, .indexed8:
            self.overdraw(at: base, brush: brush, element: UInt8.self)
        // 2-byte stride
        case .v16, .va8:
            self.overdraw(at: base, brush: brush, element: UInt16.self)
        // 3-byte stride
        case .bgr8, .rgb8:
            self.overdraw(at: base, brush: brush, element: (UInt8, UInt8, UInt8).self)
        // 4-byte stride
        case .bgra8, .rgba8, .va16:
            self.overdraw(at: base, brush: brush, element: UInt32.self)
        // 6-byte stride
        case .rgb16:
            self.overdraw(at: base, brush: brush, element: (UInt16, UInt16, UInt16).self)
        // 8-byte stride
        case .rgba16:
            self.overdraw(at: base, brush: brush, element: UInt64.self)
        }
    }

    private mutating func overdraw<T>(at base: (x: Int, y: Int), brush: (x: Int, y: Int), element: T.Type) {
        unsafe self.storage.withUnsafeMutableBytes {
            let storage: UnsafeMutableBufferPointer<T> = unsafe $0.bindMemory(to: T.self)
            for y in base.y ..< min(base.y + brush.y, self.size.y) {
                for x in stride(from: base.x, to: self.size.x, by: brush.x) {
                    let i = base.y * self.size.x + x
                    for x in x ..< min(x + brush.x, self.size.x) {
                        unsafe storage[y * self.size.x + x] = unsafe storage[i]
                    }
                }
            }
        }
    }
}

extension ArraySlice where Element == UInt8 {
    func load<T, U>(bigEndian: T.Type, as type: U.Type) -> U where T: FixedWidthInteger, U: BinaryInteger {
        return unsafe self.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) in

            assert(buffer.count >= MemoryLayout<T>.size, "attempt to load \(T.self) from slice of size \(buffer.count)")

            var storage: T = .init()
            let value: T = unsafe withUnsafeMutablePointer(to: &storage) {
                unsafe $0.deinitialize(count: 1)

                let source: UnsafeRawPointer = unsafe .init(buffer.baseAddress!),
                    raw: UnsafeMutableRawPointer = .init($0)

                unsafe raw.copyMemory(from: source, byteCount: MemoryLayout<T>.size)

                return unsafe raw.load(as: T.self)
            }

            return U(T(bigEndian: value))
        }
    }
}

extension PNGImage {
    /// Unpacks this image to a pixel array.
    ///
    /// -   Parameter _:
    ///     A color target type. This type provides the
    ///     ``PNG.Color/unpack(_:of:) [requirement]`` implementation used to unpack the image
    ///     data.
    /// -   Returns:
    ///     A pixel array. Its elements are arranged in row-major order. The
    ///     first pixel in this array corresponds to the top-left corner of
    ///     the image. Its length is equal to `size.x` multiplied by `size.y`.
    @inlinable
    public
    func unpack<Color>(as _: Color.Type) -> [Color] where Color: PNGColor {
        Color.unpack(self.storage, of: self.layout.format)
    }
}

func convolve<A, T, C>(
    _ samples: UnsafeBufferPointer<A>,
    _ kernel: (T, A) -> C,
    _ transform: (A) -> T
) -> [C] where A: FixedWidthInteger & UnsignedInteger {
    unsafe samples.map {
        let v: A = .init(bigEndian: $0)
        return kernel(transform(v), v)
    }
}

func convolve<A, T, C>(
    _ samples: UnsafeBufferPointer<A>,
    _ kernel: ((T, T)) -> C,
    _ transform: (A) -> T
) -> [C] where A: FixedWidthInteger & UnsignedInteger {
    stride(from: samples.startIndex, to: samples.endIndex, by: 2).map {
        let v: A = unsafe .init(bigEndian: samples[$0])
        let a: A = unsafe .init(bigEndian: samples[$0 &+ 1])
        return kernel((transform(v), transform(a)))
    }
}

func convolve<A, T, C>(
    _ samples: UnsafeBufferPointer<A>,
    _ kernel: ((T, T, T), (A, A, A)) -> C,
    _ transform:(A) -> T
) -> [C] where A: FixedWidthInteger & UnsignedInteger {
    stride(from: samples.startIndex, to: samples.endIndex, by: 3).map {
        let r: A = unsafe .init(bigEndian: samples[$0])
        let g: A = unsafe .init(bigEndian: samples[$0 &+ 1])
        let b: A = unsafe .init(bigEndian: samples[$0 &+ 2])
        return kernel((transform(r), transform(g), transform(b)), (r, g, b))
    }
}

func convolve<A, T, C>(
    _ samples: UnsafeBufferPointer<A>,
    _ kernel: ((T, T, T, T)) -> C,
    _ transform:(A) -> T
) -> [C] where A: FixedWidthInteger & UnsignedInteger {
    stride(from: samples.startIndex, to: samples.endIndex, by: 4).map {
        let r: A = unsafe .init(bigEndian: samples[$0     ])
        let g: A = unsafe .init(bigEndian: samples[$0 &+ 1])
        let b: A = unsafe .init(bigEndian: samples[$0 &+ 2])
        let a: A = unsafe .init(bigEndian: samples[$0 &+ 3])
        return kernel((transform(r), transform(g), transform(b), transform(a)))
    }
}

func convolve<A, T, C>(
    _ samples: UnsafeBufferPointer<UInt8>,
    _ kernel: ((T, T, T, T)) -> C,
    _ dereference: (Int) -> (A, A, A, A),
    _ transform: (A) -> T
) -> [C] where A: FixedWidthInteger & UnsignedInteger {
    unsafe samples.map {
        let (r, g, b, a): (A, A, A, A) = dereference(.init($0))
        return kernel((transform(r), transform(g), transform(b), transform(a)))
    }
}

func quantum<T>(source: Int, destination: Int) -> T where T: FixedWidthInteger & UnsignedInteger {
    // needless to say, `destination` can be no greater than `T.bitWidth`
    T.max >> (T.bitWidth - destination) / T.max >> (T.bitWidth - source)
}

/// Converts an image data buffer to a pixel array, using the given
/// pixel kernel and dereferencing function.
///
/// This function casts each byte in `buffer` to an ``Int`` index,
/// and passes each index to the given `dereference` function, receiving
/// quadruplets of atoms of type `A` in return. It then scales the atoms to the
/// range of `T`, and constructs instances of `C` by mapping the given
/// `kernel` function over each `(T, T, T, T)` quadruplet.
///
/// A worked example of how to use this function to implement a custom
/// color target can be found in the
/// [custom color targets tutorial](https://github.com/tayloraswift/swift-png/tree/master/examples#custom-color-targets).
/// -   Parameter buffer:
///     An image data buffer.
/// -   Parameter dereference:
///     A dereferencing function.
/// -   Parameter kernel:
///     A pixel kernel.
/// -   Returns:
///     An array of pixels constructed by the given `kernel` function.
///     This array has the same number of elements as `buffer`.
func convolve<A, T, C>(
    _ buffer: [UInt8],
    dereference: (Int) -> (A, A, A, A),
    kernel: ((T, T, T, T)) -> C
) -> [C] where A: FixedWidthInteger & UnsignedInteger, T: FixedWidthInteger & UnsignedInteger {
    unsafe buffer.withUnsafeBufferPointer {
        if T.bitWidth == A.bitWidth {
            return unsafe convolve($0, kernel, dereference, T.init(_:))
        } else if T.bitWidth >  A.bitWidth {
            let quantum: T = quantum(source: A.bitWidth, destination: T.bitWidth)
            return unsafe convolve($0, kernel, dereference) {
                quantum &* .init($0)
            }
        } else {
            let shift: Int = A.bitWidth - T.bitWidth
            return unsafe convolve($0, kernel, dereference) {
                .init($0 &>> shift)
            }
        }
    }
}

/// Converts an image data buffer to a pixel array, using the given
/// pixel kernel.
///
/// This function interprets `buffer` as an array of big-endian atoms of
/// type `A`. It then scales the atoms to the range of `T`, according to
/// the given color `depth`, and constructs instances of `C` by mapping
/// the given `kernel` function over consecutive `(T, T)` pairs.
///
/// A worked example of how to use this function to implement a custom
/// color target can be found in the
/// [custom color targets tutorial](https://github.com/tayloraswift/swift-png/tree/master/examples#custom-color-targets).
/// -   Parameter buffer:
///     An image data buffer. Its length must be divisible by twice the
///     stride of `A`.
/// -   Parameter _:
///     An atom type.
/// -   Parameter depth:
///     A color depth used to interpret the intensity of each atom.
///     This depth must be no greater than `A.bitWidth`.
/// -   Parameter kernel:
///     A pixel kernel.
/// -   Returns:
///     An array of pixels constructed by the given `kernel` function.
///     This array has a length of `buffer.count` divided by the twice the
///     stride of `A`.
func convolve<A, T, C>(
    _ buffer: [UInt8],
    of _: A.Type,
    depth: Int,
    kernel: ((T, T)) -> C
) -> [C] where A: FixedWidthInteger & UnsignedInteger, T: FixedWidthInteger & UnsignedInteger {
    unsafe buffer.withUnsafeBytes {
        let samples: UnsafeBufferPointer<A> = unsafe $0.bindMemory(to: A.self)
        if T.bitWidth == depth {
            return unsafe convolve(samples, kernel, T.init(_:))
        } else if T.bitWidth > depth {
            let quantum: T = quantum(source: depth, destination: T.bitWidth)
            return unsafe convolve(samples, kernel) {
                quantum &* .init($0)
            }
        } else {
            let shift: Int = depth - T.bitWidth
            return unsafe convolve(samples, kernel) {
                .init($0 &>> shift)
            }
        }
    }
}

/// Converts an image data buffer to a pixel array, using the given
/// pixel kernel.
///
/// This function interprets `buffer` as an array of big-endian atoms of
/// type `A`. It then scales the atoms to the range of `T`, according to
/// the given color `depth`, and constructs instances of `C` by mapping
/// the given `kernel` function over consecutive `(T, T, T)` triplets,
/// and the original atoms they were generated from.
///
/// A worked example of how to use this function to implement a custom
/// color target can be found in the
/// [custom color targets tutorial](https://github.com/tayloraswift/swift-png/tree/master/examples#custom-color-targets).
/// -   Parameter buffer:
///     An image data buffer. Its length must be divisible by three times the
///     stride of `A`.
/// -   Parameter _:
///     An atom type.
/// -   Parameter depth:
///     A color depth used to interpret the intensity of each atom.
///     This depth must be no greater than `A.bitWidth`.
/// -   Parameter kernel:
///     A pixel kernel.
/// -   Returns:
///     An array of pixels constructed by the given `kernel` function.
///     This array has a length of `buffer.count` divided by the three times
///     the stride of `A`.
func convolve<A, T, C>(
    _ buffer: [UInt8],
    of _: A.Type,
    depth: Int,
    kernel: ((T, T, T), (A, A, A)) -> C
) -> [C] where A: FixedWidthInteger & UnsignedInteger, T: FixedWidthInteger & UnsignedInteger {
    unsafe buffer.withUnsafeBytes {
        let samples: UnsafeBufferPointer<A> = unsafe $0.bindMemory(to: A.self)
        if T.bitWidth == depth {
            return unsafe convolve(samples, kernel, T.init(_:))
        } else if T.bitWidth > depth {
            let quantum: T = quantum(source: depth, destination: T.bitWidth)
            return unsafe convolve(samples, kernel) {
                quantum &* .init($0)
            }
        } else {
            let shift: Int = depth - T.bitWidth
            return unsafe convolve(samples, kernel) {
                .init($0 &>> shift)
            }
        }
    }
}

/// Converts an image data buffer to a pixel array, using the given
/// pixel kernel.
///
/// This function interprets `buffer` as an array of big-endian atoms of
/// type `A`. It then scales the atoms to the range of `T`, according to
/// the given color `depth`, and constructs instances of `C` by mapping
/// the given `kernel` function over consecutive `(T, T, T, T)` quadruplets.
///
/// A worked example of how to use this function to implement a custom
/// color target can be found in the
/// [custom color targets tutorial](https://github.com/tayloraswift/swift-png/tree/master/examples#custom-color-targets).
/// -   Parameter buffer:
///     An image data buffer. Its length must be divisible by four times the
///     stride of `A`.
/// -   Parameter _:
///     An atom type.
/// -   Parameter depth:
///     A color depth used to interpret the intensity of each atom.
///     This depth must be no greater than `A.bitWidth`.
/// -   Parameter kernel:
///     A pixel kernel.
/// -   Returns:
///     An array of pixels constructed by the given `kernel` function.
///     This array has a length of `buffer.count` divided by the four times
///     the stride of `A`.
func convolve<A, T, C>(
    _ buffer: [UInt8],
    of _: A.Type,
    depth: Int,
    kernel: ((T, T, T, T)) -> C
) -> [C] where A: FixedWidthInteger & UnsignedInteger, T: FixedWidthInteger & UnsignedInteger {
    unsafe buffer.withUnsafeBytes {
        let samples: UnsafeBufferPointer<A> = unsafe $0.bindMemory(to: A.self)
        if T.bitWidth == depth {
            return unsafe convolve(samples, kernel, T.init(_:))
        } else if T.bitWidth > depth {
            let quantum: T = quantum(source: depth, destination: T.bitWidth)
            return unsafe convolve(samples, kernel) {
                quantum &* .init($0)
            }
        } else {
            let shift: Int = depth - T.bitWidth
            return unsafe convolve(samples, kernel) {
                .init($0 &>> shift)
            }
        }
    }
}

// cannot genericize the kernel parameters, since it produces an unacceptable slowdown
// so we have to manually specialize for all four cases (using the exact same function body)

/// Converts an image data buffer to a pixel array, using the given
/// pixel kernel.
///
/// This function interprets `buffer` as an array of big-endian atoms of
/// type `A`. It then scales the atoms to the range of `T`, according to
/// the given color `depth`, and constructs instances of `C` by mapping
/// the given `kernel` function over each `T` scalar, and the original
/// scalar atom it was generated from.
///
/// A worked example of how to use this function to implement a custom
/// color target can be found in the
/// [custom color targets tutorial](https://github.com/tayloraswift/swift-png/tree/master/examples#custom-color-targets).
/// -   Parameter buffer:
///     An image data buffer. Its length must be divisible by the stride of `A`.
/// -   Parameter _:
///     An atom type.
/// -   Parameter depth:
///     A color depth used to interpret the intensity of each atom.
///     This depth must be no greater than `A.bitWidth`.
/// -   Parameter kernel:
///     A pixel kernel.
/// -   Returns:
///     An array of pixels constructed by the given `kernel` function.
///     This array has a length of `buffer.count` divided by the stride of `A`.
func convolve<A, T, C>(
    _ buffer: [UInt8],
    of _: A.Type,
    depth: Int,
    kernel: (T, A) -> C
) -> [C] where A: FixedWidthInteger & UnsignedInteger, T: FixedWidthInteger & UnsignedInteger {
    unsafe buffer.withUnsafeBytes {
        let samples: UnsafeBufferPointer<A> = unsafe $0.bindMemory(to: A.self)
        if T.bitWidth == depth {
            return unsafe convolve(samples, kernel, T.init(_:))
        } else if T.bitWidth >  depth {
            let quantum: T = quantum(source: depth, destination: T.bitWidth)
            return unsafe convolve(samples, kernel) {
                quantum &* .init($0)
            }
        } else {
            let shift: Int = depth - T.bitWidth
            return unsafe convolve(samples, kernel) {
                .init($0 &>> shift)
            }
        }
    }
}
