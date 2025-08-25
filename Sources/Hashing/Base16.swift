/// A namespace for base-16 utilities.
public enum Base16 {
    /// Decodes some ``String``-like type containing an ASCII-encoded base-16 string
    /// to some ``RangeReplaceableCollection`` type. The order of the decoded bytes
    /// in the output matches the order of the (pairs of) hexadecimal digits in the
    /// input string.
    ///
    /// Characters (including UTF-8 continuation bytes) that are not base-16 digits
    /// will be skipped. If the string does not contain an even number of digits,
    /// the trailing digit will be ignored.
    ///
    /// >   Warning:
    ///     This function uses the size of the input string to provide a capacity hint
    ///     for its output, and may over-allocate storage if the input contains many
    ///     non-digit characters.
    @inlinable
    static func decode<Bytes>(
        _ ascii: some StringProtocol,
        to _: Bytes.Type = Bytes.self
    ) -> Bytes where Bytes: RangeReplaceableCollection<UInt8> {
        self.decode(ascii.utf8, to: Bytes.self)
    }

    /// Decodes an ASCII-encoded base-16 string to some ``RangeReplaceableCollection`` type.
    /// The order of the decoded bytes in the output matches the order of the (pairs of)
    /// hexadecimal digits in the input.
    ///
    /// Characters (including UTF-8 continuation bytes) that are not base-16 digits
    /// will be skipped. If the input does not yield an even number of digits, the
    /// trailing digit will be ignored.
    ///
    /// >   Warning:
    ///     This function uses the size of the input string to provide a capacity hint
    ///     for its output, and may over-allocate storage if the input contains many
    ///     non-digit characters.
    @inlinable
    static func decode<ASCII, Bytes>(
        _ ascii: ASCII,
        to _: Bytes.Type = Bytes.self
    ) -> Bytes where Bytes: RangeReplaceableCollection<UInt8>, ASCII: Sequence<UInt8> {
        var bytes:Bytes = .init()
        bytes.reserveCapacity(ascii.underestimatedCount / 2)
        var values: Values<ASCII> = .init(ascii)
        while let high: UInt8 = values.next(), let low: UInt8 = values.next() {
            bytes.append(high << 4 | low)
        }
        return bytes
    }
    
    /// Encodes a sequence of bytes to a base-16 string with the specified lettercasing.
    @inlinable
    public static func encode<Digits>(_ bytes: some Sequence<UInt8>, with _: Digits.Type) -> String where Digits: BaseDigits {
        var encoded: String = ""
        encoded.reserveCapacity(bytes.underestimatedCount * 2)
        for byte: UInt8 in bytes {
            encoded.append(Digits[byte >> 4])
            encoded.append(Digits[byte & 0x0f])
        }
        return encoded
    }
}

extension Base16 {
    /// Decodes an ASCII-encoded base-16 string into a pre-allocated buffer,
    /// returning `nil` if the input did not yield enough digits to fill
    /// the buffer completely.
    ///
    /// Characters (including UTF-8 continuation bytes) that are not base-16 digits
    /// will be skipped.
    @inlinable
    static func decode<ASCII>(_ ascii: ASCII, into bytes: UnsafeMutableRawBufferPointer) -> Void? where ASCII: Sequence<UInt8> {
        var values: Values<ASCII> = .init(ascii)
        for offset: Int in bytes.indices {
            if let high: UInt8 = values.next(), let low: UInt8 = values.next() {
                unsafe bytes[offset] = high << 4 | low
            } else {
                return nil
            }
        }
        return ()
    }

    /// Encodes a sequence of bytes into a pre-allocated buffer as a base-16
    /// string with the specified lettercasing.
    ///
    /// The size of the `ascii` buffer must be exactly twice the inline size
    /// of `words`. If this method is used incorrectly, the output buffer may
    /// be incompletely initialized, but it will never write to memory outside
    /// of the buffer’s bounds.
    @inlinable
    public static func encode<BigEndian, Digits>(
        storing words: BigEndian,
        into ascii: UnsafeMutableRawBufferPointer,
        with _: Digits.Type
    ) where Digits: BaseDigits {
        unsafe withUnsafeBytes(of: words) {
            assert(2 * $0.count <= ascii.count)

            for unsafe (offset, byte): (Int, UInt8) in unsafe zip(stride(from: ascii.startIndex, to: ascii.endIndex, by: 2), $0) {
                unsafe ascii[offset] = Digits[byte >> 4]
                unsafe ascii[offset + 1] = Digits[byte & 0x0f]
            }
        }
    }
}

extension Base16 {
    /// Decodes an ASCII-encoded base-16 string to some (usually trivial) type.
    /// This is essentially the same as loading values from raw memory, so this
    /// method should only be used to load trivial types.
    @inlinable
    static func decode<BigEndian>(_ ascii: some Sequence<UInt8>, loading _: BigEndian.Type = BigEndian.self) -> BigEndian? {
        unsafe withUnsafeTemporaryAllocation(byteCount: MemoryLayout<BigEndian>.size, alignment: MemoryLayout<BigEndian>.alignment) {
            let words: UnsafeMutableRawBufferPointer = unsafe $0
            if case _? = unsafe Self.decode(ascii, into: words) {
                return unsafe $0.load(as: BigEndian.self)
            } else {
                return nil
            }
        }
    }

    /// Encodes the raw bytes of the given value to a base-16 string with the
    /// specified lettercasing. The bytes with the lowest addresses appear first
    /// in the encoded output.
    ///
    /// This method is slightly faster than calling ``encode(_:with:)`` on an
    /// unsafe buffer-pointer view of `words`.
    @inlinable
    public static func encode<BigEndian, Digits>(storing words: BigEndian, with _: Digits.Type) -> String where Digits: BaseDigits {
        let bytes: Int = 2 * MemoryLayout<BigEndian>.size

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 14.0, *) {
            return unsafe .init(unsafeUninitializedCapacity: bytes) {
                unsafe Self.encode(storing: words, into: UnsafeMutableRawBufferPointer.init($0), with: Digits.self)
                return bytes
            }
        }
#endif

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        return unsafe .init(
            decoding: [UInt8].init(unsafeUninitializedCapacity: bytes) {
                unsafe Self.encode(storing: words, into: UnsafeMutableRawBufferPointer.init($0), with: Digits.self)
                $1 = bytes
            },
            as: Unicode.UTF8.self
        )
#else
        return .init(unsafeUninitializedCapacity: bytes) {
            Self.encode(storing: words, into: UnsafeMutableRawBufferPointer.init($0), with: Digits.self)
            return bytes
        }
#endif
    }
}


// MARK: Values

extension Base16 {
    /// An abstraction over text input, which discards characters that are not
    /// valid base-16 digits.
    public struct Values<ASCII> where ASCII: Sequence<UInt8> {
        public var iterator: ASCII.Iterator

        @inlinable
        init(_ ascii: ASCII) {
            self.iterator = ascii.makeIterator()
        }
    }
}

extension Base16.Values: Sequence, IteratorProtocol {
    public typealias Iterator = Self

    @inlinable
    public mutating func next() -> UInt8? {
        while let digit: UInt8 = self.iterator.next() {
            switch digit {
            case 0x30 ... 0x39:
                return digit - 0x30
            case 0x61 ... 0x66:
                return digit + 10 - 0x61
            case 0x41 ... 0x46:
                return digit + 10 - 0x41
            default:
                continue
            }
        }
        return nil
    }
}


extension Base16 {
    public enum LowercaseDigits {}
}
extension Base16.LowercaseDigits: BaseDigits {
    @inlinable
    public static subscript(remainder: UInt8) -> UInt8 {
        (remainder < 10 ? 0x30 : 0x61 - 10) &+ remainder
    }
}

extension Base16 {
    enum UppercaseDigits {}
}
extension Base16.UppercaseDigits: BaseDigits {
    @inlinable
    static subscript(remainder: UInt8) -> UInt8 {
        (remainder < 10 ? 0x30 : 0x41 - 10) &+ remainder
    }
}
