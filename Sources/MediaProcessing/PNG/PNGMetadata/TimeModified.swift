extension PNGMetadata {
    /// An image modification time.
    ///
    /// This type models the information stored in a ``Chunk/tIME`` chunk.
    /// This type is time-zone agnostic, and so all time values are assumed
    /// to be in universal time (UTC).
    struct TimeModified {
        /// The complete [gregorian](https://en.wikipedia.org/wiki/Gregorian_calendar) year.
        let year: Int
        /// The calendar month, expressed as a 1-indexed integer.
        let month: Int
        /// The calendar day, expressed as a 1-indexed integer.
        let day: Int
        /// The hour, in 24-hour time, expressed as a 0-indexed integer.
        let hour: Int
        /// The minute, expressed as a 0-indexed integer.
        let minute: Int
        /// The second, expressed as a 0-indexed integer.
        let second: Int
    }
}

extension PNGMetadata.TimeModified {
    /// Creates an image modification time by parsing the given chunk data.
    /// -   Parameter data:
    ///     The contents of a ``Chunk/tIME`` chunk to parse.
    init(parsing data:[UInt8]) throws
    {
        guard data.count == 7 else {
            throw PNGImage.ParsingError.invalidTimeModifiedChunkLength(data.count)
        }

        self.year = data.load(bigEndian: UInt16.self, as: Int.self, at: 0)
        self.month = .init(data[2])
        self.day = .init(data[3])
        self.hour = .init(data[4])
        self.minute = .init(data[5])
        self.second = .init(data[6])

        guard 0 ..< 1 << 16 ~= self.year,
            1 ... 12 ~= self.month,
            1 ... 31 ~= self.day,
            0 ... 23 ~= self.hour,
            0 ... 59 ~= self.minute,
            0 ... 60 ~= self.second
        else {
            throw PNGImage.ParsingError.invalidTimeModifiedTime(
                year: self.year,
                month: self.month,
                day: self.day,
                hour: self.hour,
                minute: self.minute,
                second: self.second
            )
        }
    }
}

extension PNGMetadata.TimeModified: CustomStringConvertible {
    var description: String {
        """
        PNG.\(Self.self) (\(PNGChunkIdentifier.tIME))
        {
            year: \(self.year)
            month: \(self.month)
            day: \(self.day)
            hour: \(self.hour)
            minute: \(self.minute)
            second: \(self.second)
        }
        """
    }
}
