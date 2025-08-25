extension PNGMetadata {
    /// A suggested image palette.
    ///
    /// This type models the information stored in an ``Chunk/sPLT`` chunk.
    /// It should not be confused with the suggested palette stored in the
    /// color ``Format`` of an RGB, BGR, RGBA, or BGRA image.
    struct SuggestedPalette {
        /// The name of this suggested palette.
        let name: String
        /// The colors in this suggested palette, and their frequencies.
        var entries: Entries

        /// A variant array of palette colors and frequencies.
        enum Entries {
            /// A suggested palette with an 8-bit color depth.
            /// -   Parameter _:
            ///     An array of 8-bit palette colors and frequencies.
            case rgba8([(color: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), frequency: UInt16)])
            /// A suggested palette with a 16-bit color depth.
            /// -   Parameter _:
            ///     An array of 16-bit palette colors and frequencies.
            case rgba16([(color: (r: UInt16, g: UInt16, b: UInt16, a: UInt16), frequency: UInt16)])
        }

    }
}

extension PNGMetadata.SuggestedPalette {
    /// Creates a suggested palette by parsing the given chunk data.
    /// -   Parameter data:
    ///     The contents of an ``Chunk/sPLT`` chunk to parse.
    init(parsing data:[UInt8]) throws {
        let k: Int

        (self.name, k) = try PNGMetadata.Text.name(parsing: data[...]) {
            PNGImage.ParsingError.invalidSuggestedPaletteName($0)
        }

        guard k + 1 < data.count else {
            throw PNGImage.ParsingError.invalidSuggestedPaletteChunkLength(data.count, min: k + 2)
        }

        let bytes = data.count - k - 2
        switch data[k + 1] {
        case 8:
            guard bytes % 6 == 0 else {
                throw PNGImage.ParsingError.invalidSuggestedPaletteDataLength(bytes, stride: 6)
            }

            self.entries = .rgba8(
                stride(from: k + 2, to: data.endIndex, by: 6)
                    .map { (base: Int) -> (color: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), frequency: UInt16) in
                        ((
                            data[base],
                            data[base + 1],
                            data[base + 2],
                            data[base + 3]
                        ), data.load(bigEndian: UInt16.self, as: UInt16.self, at: base + 4))
                    }
            )

        case 16:
            guard bytes % 10 == 0 else {
                throw PNGImage.ParsingError.invalidSuggestedPaletteDataLength(bytes, stride: 10)
            }

            self.entries = .rgba16(
                stride(from: k + 2, to: data.endIndex, by: 10)
                    .map { (base: Int) -> (color: (r: UInt16, g: UInt16, b: UInt16, a: UInt16), frequency: UInt16) in
                        ((
                            data.load(bigEndian: UInt16.self, as: UInt16.self, at: base    ),
                            data.load(bigEndian: UInt16.self, as: UInt16.self, at: base + 2),
                            data.load(bigEndian: UInt16.self, as: UInt16.self, at: base + 4),
                            data.load(bigEndian: UInt16.self, as: UInt16.self, at: base + 6)
                        ), data.load(bigEndian: UInt16.self, as: UInt16.self, at: base + 8))
                    }
            )

        case let code:
            throw PNGImage.ParsingError.invalidSuggestedPaletteDepthCode(code)
        }

        guard self.descendingFrequency else {
            throw PNGImage.ParsingError.invalidSuggestedPaletteFrequency
        }
    }

    private var descendingFrequency: Bool {
        var previous: UInt16 = .max
        switch self.entries {
        case .rgba8(let entries):
            for current in entries.lazy.map(\.frequency) {
                guard current <= previous else {
                    return false
                }

                previous = current
            }
        case .rgba16(let entries):
            for current in entries.lazy.map(\.frequency) {
                guard current <= previous else {
                    return false
                }

                previous = current
            }
        }

        return true
    }
}
