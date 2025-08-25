import _MediaProcessingShims

func rgbaToThumbHash(width: Int, height: Int, rgba: [UInt8]) -> [UInt8] {
    assert(width <= 100 && height <= 100, "Encoding an image larger than 100x100 is slow with no benefit")
    assert(rgba.count == (width * height * 4))

    var averageRed: Float = 0.0
    var averageGreen: Float = 0.0
    var averageBlue: Float = 0.0
    var averageAlpha: Float = 0.0
    for (index, rgba) in stride(from: 0, to: rgba.count, by: 4).map({ ($0, rgba[$0..<min($0 + 4, rgba.count)]) }) {
        let alpha = Float(rgba[index + 3]) / 255.0
        averageRed += alpha / 255.0 * Float(rgba[index + 0])
        averageGreen += alpha / 255.0 * Float(rgba[index + 1])
        averageBlue += alpha / 255.0 * Float(rgba[index + 2])
        averageAlpha += alpha
    }
    if averageAlpha > 0 {
        averageRed /= averageAlpha
        averageGreen /= averageAlpha
        averageBlue /= averageAlpha
    }

    let hasAlpha = averageAlpha < Float(width * height)
    let luminanceLimit = hasAlpha ? 5 : 7 // use fewer luminance bits if there's alpha
    let luminanceX = max(Int(Float(luminanceLimit * width) / Float(max(width, height))), 1)
    let luminanceY = max(Int(Float(luminanceLimit * height) / Float(max(width, height))), 1)
    var l = [Float]() // luminance
    var p = [Float]() // yellow - blue
    var q = [Float]() // red - green
    var a = [Float]() // alpha
    l.reserveCapacity(width * height)
    p.reserveCapacity(width * height)
    q.reserveCapacity(width * height)
    a.reserveCapacity(width * height)

    // Convert the image from RGBA to LPQA (composite atop the average color)
    for (index, rgba) in stride(from: 0, to: rgba.count, by: 4).map({ ($0, rgba[$0..<min($0 + 4, rgba.count)]) }) {
        let alpha = Float(rgba[index + 3]) / 255.0
        let red = averageRed * (1.0 - alpha) + alpha / 255.0 * Float(rgba[index + 0])
        let green = averageGreen * (1.0 - alpha) + alpha / 255.0 * Float(rgba[index + 1])
        let blue = averageBlue * (1.0 - alpha) + alpha / 255.0 * Float(rgba[index + 2])
        l.append((red + green + blue) / 3.0)
        p.append((red + green) / 2.0 - blue)
        q.append(red - green)
        a.append(alpha)
    }

    // Encode using the DCT into DC (constant) and normalized AC (varying) terms
    func encodeChannel(channel: [Float], nx: Int, ny: Int) -> (Float, [Float], Float) {
        var dc: Float = 0.0
        var ac = [Float]()
        ac.reserveCapacity(nx * ny / 2)
        var scale: Float = 0.0
        var fx = [Float](repeating: 0.0, count: width)
        for cy in 0..<ny {
            var cx = 0
            while cx * ny < nx * (ny - cy) {
                var f: Float = 0.0
                for x in 0..<width {
                    fx[x] = libm_cosf(.pi / Float(width) * Float(cx) * (Float(x) + 0.5))
                }
                for y in 0..<height {
                    let fy = libm_cosf(.pi / Float(height) * Float(cy) * (Float(y) + 0.5))
                    for x in 0..<width {
                        f += channel[x + y * width] * fx[x] * fy
                    }
                }
                f /= Float(width * height)
                if cx > 0 || cy > 0 {
                    ac.append(f)
                    scale = max(abs(f), scale)
                } else {
                    dc = f
                }
                cx += 1
            }
        }
        if scale > 0.0 {
            for index in ac.indices {
                ac[index] = 0.5 + 0.5 / scale * ac[index]
            }
        }
        return (dc, ac, scale)
    }
    let (l_dc, l_ac, l_scale) = encodeChannel(channel: l, nx: max(luminanceX, 3), ny: max(luminanceY, 3))
    let (p_dc, p_ac, p_scale) = encodeChannel(channel: p, nx: 3, ny: 3)
    let (q_dc, q_ac, q_scale) = encodeChannel(channel: q, nx: 3, ny: 3)
    let (a_dc, a_ac, a_scale) = hasAlpha ? encodeChannel(channel: a, nx: 5, ny: 5) : (1.0, [], 1.0)

    // Write the constants
    let isLandscape = width > height
    func round32(_ value: Float) -> UInt32 {
        UInt32(value.rounded())
    }
    let header24 = round32(63.0 * l_dc)
    | (round32(31.5 + 31.5 * p_dc) << 6)
    | (round32(31.5 + 31.5 * q_dc) << 12)
    | (round32(31.0 * l_scale) << 18)
    | (hasAlpha ? 1 << 23 : 0)
    func round16(_ value: Float) -> UInt16 {
        UInt16(value.rounded())
    }
    let header16 = UInt16(isLandscape ? luminanceY : luminanceX)
    | (round16(63.0 * p_scale) << 3)
    | (round16(63.0 * q_scale) << 9)
    | (isLandscape ? 1 << 15 : 0)
    var hash = [UInt8]()
    hash.reserveCapacity(25)
    hash.append(contentsOf: [
        UInt8(header24 & 255),
        UInt8((header24 >> 8) & 255),
        UInt8(header24 >> 16),
        UInt8(header16 & 255),
        UInt8(header16 >> 8)
    ])
    var isOdd = false
    if hasAlpha {
        hash.append(UInt8((15 * a_dc).rounded()) | (UInt8((15.0 * a_scale).rounded()) << 4))
    }

    // Write the varying factors
    for ac in [l_ac, p_ac, q_ac] {
        for f in ac {
            let u = UInt8((15.0 * f).rounded())
            if isOdd {
                hash[hash.endIndex - 1] |= u << 4
            } else {
                hash.append(u)
            }
            isOdd = !isOdd
        }
    }
    if hasAlpha {
        for f in a_ac {
            let u = UInt8((15.0 * f).rounded())
            if isOdd {
                hash[hash.endIndex - 1] |= u << 4
            } else {
                hash.append(u)
            }
            isOdd = !isOdd
        }
    }
    return hash
}
