extension PNGMetadata {
    /// A physical dimensions descriptor.
    ///
    /// This type models the information stored in a ``Chunk/pHYs`` chunk.
    struct PhysicalDimensions {
        /// A unit of measurement.
        enum Unit {
            /// The meter.
            ///
            /// For conversion purposes, one inch is assumed to equal exactly
            /// `254 / 10000` meters.
            case meter
        }

        /// The number of pixels in each dimension per the given `unit` of measurement.
        ///
        /// If `unit` is `nil`, the pixel density is unknown,
        /// and the `x` and `y` values specify the pixel aspect ratio only.
        let density: (x: Int, y: Int, unit: Unit?)
    }
}

extension PNGMetadata.PhysicalDimensions {
    /// Creates a physical dimensions descriptor by parsing the given chunk data.
    /// -   Parameter data:
    ///     The contents of a ``Chunk/pHYs`` chunk to parse.
    init(parsing data: [UInt8]) throws {
        guard data.count == 9 else {
            throw PNGImage.ParsingError.invalidPhysicalDimensionsChunkLength(data.count)
        }

        self.density.x = data.load(bigEndian: UInt32.self, as: Int.self, at: 0)
        self.density.y = data.load(bigEndian: UInt32.self, as: Int.self, at: 4)

        switch data[8] {
        case 0: self.density.unit = nil
        case 1: self.density.unit = .meter
        case let code:
            throw PNGImage.ParsingError.invalidPhysicalDimensionsDensityUnitCode(code)
        }
    }
}

extension PNGMetadata.PhysicalDimensions: CustomStringConvertible {
    var description: String {
        """
        PNG.\(Self.self) (\(PNGChunkIdentifier.pHYs)) {
            density: (x: \(self.density.x), y: \(self.density.y)) \(self.density.unit.map{ "/ \($0)" } ?? "(no units)")
        }
        """
    }
}
