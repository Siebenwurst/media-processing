/// A chunk type identifier.
struct PNGChunkIdentifier: Hashable, Equatable, CustomStringConvertible
{
    /// The chunk type code.
    let name: UInt32

    /// A string displaying the ASCII representation of this chunk type identifier.
    var description: String {
        unsafe withUnsafeBytes(of: self.name.bigEndian) {
            unsafe .init(decoding: $0, as: Unicode.ASCII.self)
        }
    }

    init(unchecked name: UInt32) {
        self.name = name
    }

    /// Creates a chunk type identifier, returning `nil` if the type code
    /// is invalid.
    ///
    /// This initializer is a non-trapping version of ``init(name:)``.
    /// -   Parameter name:
    ///     The chunk type code. Bit 13 must be set. If the type code is not
    ///     a public PNG chunk type code, then bit 29 must be clear.
    init?(validating name: UInt32) {
        let chunk: Self = .init(unchecked: name)
        switch chunk {
        // legal public chunks
        case    .CgBI, .IHDR, .PLTE, .IDAT, .IEND,
                .cHRM, .gAMA, .iCCP, .sBIT, .sRGB, .bKGD, .hIST, .tRNS,
                .pHYs, .sPLT, .tIME, .iTXt, .tEXt, .zTXt:
            break

        default:
            guard chunk.name & 0x20_00_20_00 == 0x20_00_00_00 else {
                return nil
            }
        }
        self.name = name
    }

    /// The `CgBI` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x43674249`.
    static let CgBI: Self = .init(unchecked: 0x43_67_42_49)
    /// The `IHDR` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x49484452`.
    static let IHDR: Self = .init(unchecked: 0x49_48_44_52)
    /// The `PLTE` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x504c5445`.
    static let PLTE: Self = .init(unchecked: 0x50_4c_54_45)
    /// The `IDAT` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x49444154`.
    static let IDAT: Self = .init(unchecked: 0x49_44_41_54)
    /// The `IEND` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x49454e44`.
    static let IEND: Self = .init(unchecked: 0x49_45_4e_44)

    /// The `cHRM` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x6348524d`.
    static let cHRM: Self = .init(unchecked: 0x63_48_52_4d)
    /// The `gAMA` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x67414d41`.
    static let gAMA: Self = .init(unchecked: 0x67_41_4d_41)
    /// The `iCCP` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x69434350`.
    static let iCCP: Self = .init(unchecked: 0x69_43_43_50)
    /// The `sBIT` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x73424954`.
    static let sBIT: Self = .init(unchecked: 0x73_42_49_54)
    /// The `sRGB` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x73524742`.
    static let sRGB: Self = .init(unchecked: 0x73_52_47_42)
    /// The `bKGD` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x624b4744`.
    static let bKGD: Self = .init(unchecked: 0x62_4b_47_44)
    /// The `hIST` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x68495354`.
    static let hIST: Self = .init(unchecked: 0x68_49_53_54)
    /// The `tRNS` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x74524e53`.
    static let tRNS: Self = .init(unchecked: 0x74_52_4e_53)

    /// The `pHYs` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x70485973`.
    static let pHYs: Self = .init(unchecked: 0x70_48_59_73)

    /// The `sPLT` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x73504c54`.
    static let sPLT: Self = .init(unchecked: 0x73_50_4c_54)
    /// The `tIME` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x74494d45`.
    static let tIME: Self = .init(unchecked: 0x74_49_4d_45)

    /// The `iTXt` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x69545874`.
    static let iTXt: Self = .init(unchecked: 0x69_54_58_74)
    /// The `tEXt` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x74455874`.
    static let tEXt: Self = .init(unchecked: 0x74_45_58_74)
    /// The `zTXt` chunk type.
    ///
    /// The numerical type code for this type identifier is `0x7a545874`.
    static let zTXt: Self = .init(unchecked: 0x7a_54_58_74)
}
