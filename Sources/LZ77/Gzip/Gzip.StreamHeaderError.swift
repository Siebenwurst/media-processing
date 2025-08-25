extension Gzip {
    @frozen
    public enum StreamHeaderError: Error, Sendable {
        case invalidSigil
        case invalidCompressionMethod(UInt8)
        case invalidFlagBits(UInt8)

        case _headerChecksumUnsupported
    }
}
