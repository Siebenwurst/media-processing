extension LZ77 {
    /// Modular redundancy check (similar to ``CRC32``)
    @frozen @usableFromInline
    struct MRC32 {
        @usableFromInline
        var single: UInt32
        @usableFromInline
        var double: UInt32

        @inlinable
        init() {
            self.single = 1
            self.double = 0
        }
    }
}

extension LZ77.MRC32: LZ77.StreamIntegral {
    // software.intel.com/content/www/us/en/develop/articles/fast-computation-of-adler32-checksums
    // link also says to use simd vectorization, but that just seems to slow
    // things down (probably because llvm is already autovectorizing it)
    @inlinable
    mutating func update(from start: UnsafePointer<UInt8>, count: Int) {
        let (q, r): (Int, Int) = count.quotientAndRemainder(dividingBy: 5552)
        for i: Int in 0 ..< q {
            for j: Int in 5552 * i ..< 5552 * (i + 1) {
                self.single &+= .init(start[j])
                self.double &+= self.single
            }
            self.single %= 65521
            self.double %= 65521
        }
        for j: Int in 5552 * q ..< 5552 * q + r {
            self.single &+= .init(start[j])
            self.double &+= self.single
        }

        self.single %= 65521
        self.double %= 65521
    }

    @inlinable
    var checksum: UInt32 { self.double << 16 | self.single }
}
