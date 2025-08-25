import _LZ77

let adam7: [(base: (x: Int, y: Int), exponent: (x: Int, y: Int))] = [
    (base: (0, 0), exponent: (3, 3)),
    (base: (4, 0), exponent: (3, 3)),
    (base: (0, 4), exponent: (2, 3)),
    (base: (2, 0), exponent: (2, 2)),
    (base: (0, 2), exponent: (1, 2)),
    (base: (1, 0), exponent: (1, 1)),
    (base: (0, 1), exponent: (0, 1)),
]

struct PNGDecoder {
    private var row: (index: Int, reference: [UInt8])?
    private var pass: Int?
    private(set) var `continue`: Void?
    private var inflator: LZ77.Inflator
}


extension PNGDecoder {
    init(standard: PNGImage.Standard, interlaced: Bool) {
        self.row = nil
        self.pass = interlaced ? 0 : nil
        self.continue = ()

        let format: LZ77.Format
        switch standard {
        case .common:
            format = .zlib
        case .ios:
            format = .ios
        }

        self.inflator = .init(format: format)
    }

    mutating func push(
        _ data: [UInt8],
        size: (x: Int, y: Int),
        pixel: PNGFormat.Pixel,
        delegate: (UnsafeBufferPointer<UInt8>, (x:Int, y:Int), (x:Int, y:Int)) throws -> ()
    ) throws -> Void? {
        guard let _: Void = self.continue
        else
        {
            throw PNGImage.DecodingError.extraneousImageDataCompressedData
        }

        self.continue = try self.inflator.push(data[...])

        let delay = (pixel.volume + 7) >> 3
        if let pass = self.pass {
            for z: Int in pass ..< 7 {
                let (base, exponent): ((x: Int, y: Int), (x: Int, y: Int)) = adam7[z]
                let stride: (x: Int, y: Int) = (x: 1 << exponent.x, y: 1 << exponent.y)
                let subimage:(x: Int, y: Int) = (
                    x: (size.x + stride.x - base.x - 1 ) >> exponent.x,
                    y: (size.y + stride.y - base.y - 1 ) >> exponent.y
                )

                guard subimage.x > 0, subimage.y > 0 else {
                    continue
                }

                let pitch = (subimage.x * pixel.volume + 7) >> 3
                var (start, last): (Int, [UInt8]) = self.row ?? (0, .init(repeating: 0, count: pitch + 1))
                self.row = nil
                for y in start ..< subimage.y {
                    guard var scanline:[UInt8] = self.inflator.pull(last.count) else {
                        self.row  = (y, last)
                        self.pass = z
                        return self.continue
                    }

                    #if DUMP_FILTERED_SCANLINES
                    print("< scanline(\(scanline[0]))[\(scanline.dropFirst().prefix(8).map(String.init(_:)).joined(separator: ", ")) ... ]")
                    #endif

                    Self.defilter(&scanline, last: last, delay: delay)

                    let base: (x: Int, y: Int) = (base.x, base.y + y * stride.y)
                    try unsafe scanline.dropFirst().withUnsafeBufferPointer {
                        try unsafe delegate($0, base, stride)
                    }

                    last = scanline
                }
            }
        } else {
            let pitch = (size.x * pixel.volume + 7) >> 3

            var (start, last): (Int, [UInt8]) = self.row ?? (0, .init(repeating: 0, count: pitch + 1))
            self.row = nil
            for y in start ..< size.y {
                guard var scanline:[UInt8] = self.inflator.pull(last.count) else {
                    self.row  = (y, last)
                    return self.continue
                }

                #if DUMP_FILTERED_SCANLINES
                print("< scanline(\(scanline[0]))[\(scanline.dropFirst().prefix(8).map(String.init(_:)).joined(separator: ", ")) ... ]")
                #endif

                Self.defilter(&scanline, last: last, delay: delay)
                try unsafe scanline.dropFirst().withUnsafeBufferPointer
                {
                    try unsafe delegate($0, (0, y), (1, 1))
                }

                last = scanline
            }
        }

        self.pass = 7
        guard self.inflator.pull().isEmpty else {
            throw PNGImage.DecodingError.extraneousImageData
        }
        return self.continue
    }

    static func defilter(_ line: inout [UInt8], last: [UInt8], delay: Int) {
        let indices:Range<Int> = line.indices.dropFirst()
        switch line[line.startIndex] {
        case 0:
            break

        case 1: // sub
            for i in indices.dropFirst(delay) {
                line[i] &+= line[i &- delay]
            }

        case 2: // up
            for i in indices {
                line[i] &+= last[i]
            }

        case 3: // average
            for i in indices.prefix(delay) {
                line[i] &+= last[i] >> 1
            }
            for i in indices.dropFirst(delay) {
                let total:UInt16 = .init(line[i &- delay]) &+ .init(last[i])
                line[i] &+= .init(total >> 1)
            }

        case 4: // paeth
            for i in indices.prefix(delay) {
                line[i] &+= paeth(0, last[i], 0)
            }
            for i in indices.dropFirst(delay) {
                line[i] &+= paeth(line[i &- delay], last[i], last[i &- delay])
            }

        default:
            break // invalid
        }
    }
}

func paeth(_ a: UInt8, _ b: UInt8, _ c: UInt8) -> UInt8 {
    // abs here is poorly-predicted so it benefits from this
    // branchless implementation
    func abs(_ x: Int16) -> Int16 {
        let mask:Int16 = x >> 15
        return (x ^ mask) + (mask & 1)
    }

    let v: (Int16, Int16, Int16) = (.init(a), .init(b), .init(c))
    let d: (Int16, Int16)        = (v.1 - v.2, v.0 - v.2)
    let f: (Int16, Int16, Int16) = (abs(d.0), abs(d.1), abs(d.0 + d.1))

    let p:(UInt8, UInt8, UInt8) = (
        .init(truncatingIfNeeded: (f.1 - f.0) >> 15), // 0x00 if f.0 <= f.1 else 0xff
        .init(truncatingIfNeeded: (f.2 - f.0) >> 15),
        .init(truncatingIfNeeded: (f.2 - f.1) >> 15)
    )

    return ~(p.0 | p.1) & a | (p.0 | p.1) & (b & ~p.2 | c & p.2)
}
