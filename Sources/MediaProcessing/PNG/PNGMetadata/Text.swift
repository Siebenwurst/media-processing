import _LZ77

extension PNGMetadata {
    /// A text comment.
    ///
    /// This type models the information stored in a ``Chunk/tEXt``,
    /// ``Chunk/zTXt``, or ``Chunk/iTXt`` chunk.
    struct Text {
        /// Indicates if the text is (or is to be) stored in compressed or
        /// uncompressed form within a PNG file.
        ///
        /// This flag is `true` if the original text chunk was a
        /// ``Chunk/zTXt`` chunk, and `false` if it was a ``Chunk/tEXt``
        /// chunk. If the original chunk was an ``Chunk/iTXt`` chunk,
        /// this flag can be either `true` or `false`.
        let compressed: Bool
        /// A keyword tag, in english, and possibly a non-english language.
        ///
        /// If the text is in english, the `localized` keyword is the empty string `""`.
        let keyword: (english: String, localized: String)
        /// An array representing an [rfc-1766](https://www.ietf.org/rfc/rfc1766.txt)
        /// language tag, where each element is a language subtag.
        ///
        /// If this array is empty, then the language is unspecified.
        let language: [String]
        /// The text content.
        let content: String
    }
}

extension PNGMetadata.Text {
    /// Creates a text comment by parsing the given chunk data, interpreting
    /// it either as a unicode text chunk, or a latin-1 text chunk.
    /// -   Parameter data:
    ///     The contents of a ``Chunk/tEXt``, ``Chunk/zTXt``, or ``Chunk/iTXt``
    ///     chunk to parse.
    /// -   Parameter unicode:
    ///     Specifies if the given chunk `data` should be interpreted as a
    ///     unicode chunk, or a latin-1 chunk. It should be set to `true` if the
    ///     original text chunk was an ``Chunk/iTXt`` chunk, and `false`
    ///     otherwise. The default value is `true`.
    ///
    ///     If this flag is set to `false`, the text is assumed to be in english,
    ///     and the ``language`` tag will be set to `["en"]`.
    init(parsing data: [UInt8], unicode: Bool = true) throws {
        //  ┌ ╶ ╶ ╶ ╶ ╶ ╶┬───┬───┬───┬ ╶ ╶ ╶ ╶ ╶ ╶┬───┬ ╶ ╶ ╶ ╶ ╶ ╶┬───┬ ╶ ╶ ╶ ╶ ╶ ╶┐
        //  │   keyword  │ 0 │ C │ M │  language  │ 0 │   keyword  │ 0 │    text    │
        //  └ ╶ ╶ ╶ ╶ ╶ ╶┴───┴───┴───┴ ╶ ╶ ╶ ╶ ╶ ╶┴───┴ ╶ ╶ ╶ ╶ ╶ ╶┴───┴ ╶ ╶ ╶ ╶ ╶ ╶┘
        //               k  k+1 k+2 k+3           l  l+1           m  m+1
        let k: Int
        (self.keyword.english, k) = try Self.name(parsing: data[...]) {
            PNGImage.ParsingError.invalidTextEnglishKeyword($0)
        }

        // parse iTXt chunk
        if unicode {
            // assert existence of compression flag and method bytes
            guard k + 2 < data.endIndex else {
                throw PNGImage.ParsingError.invalidTextChunkLength(data.count, min: k + 3)
            }

            let l: Int
            // language can be empty, in which case it is unknown
            (self.language, l) = try Self.language(parsing: data[(k + 3)...]) {
                PNGImage.ParsingError.invalidTextLanguageTag($0)
            }

            guard let m: Int = data[(l + 1)...].firstIndex(of: 0) else {
                throw PNGImage.ParsingError.invalidTextLocalizedKeyword
            }

            let localized: String = .init(decoding: data[l + 1 ..< m], as: Unicode.UTF8.self)
            self.keyword.localized = self.keyword.english == localized ? "" : localized

            let uncompressed: ArraySlice<UInt8>
            switch data[k + 1] {
            case 0:
                uncompressed = data[(m + 1)...]
                self.compressed = false
            case 1:
                guard data[k + 2] == 0 else {
                    throw PNGImage.ParsingError.invalidTextCompressionMethodCode(data[k + 2])
                }
                var inflator: LZ77.Inflator = .init()
                guard case nil = try inflator.push(data[(m + 1)...]) else {
                    throw PNGImage.ParsingError.incompleteTextCompressedDatastream
                }
                uncompressed = inflator.pull()[...]
                self.compressed = true
            case let code:
                throw PNGImage.ParsingError.invalidTextCompressionCode(code)
            }

            self.content = .init(decoding: uncompressed, as: Unicode.UTF8.self)
        } /* parse tEXt/zTXt chunk */ else {
            self.keyword.localized = ""
            self.language = ["en"]
            // if the next byte is also null, the chunk uses compression
            let uncompressed: ArraySlice<UInt8>
            if k + 1 < data.endIndex, data[k + 1] == 0 {
                var inflator:LZ77.Inflator = .init()
                guard case nil = try inflator.push(data[(k + 2)...]) else {
                    throw PNGImage.ParsingError.incompleteTextCompressedDatastream
                }
                uncompressed = inflator.pull()[...]
                self.compressed = true
            } else {
                uncompressed = data[(k + 1)...]
                self.compressed = false
            }

            self.content = .init(uncompressed.map{ Character.init(Unicode.Scalar.init($0)) })
        }
    }

    static func name<E>(parsing data: ArraySlice<UInt8>, else error: (String?) -> E) throws -> (name:String, offset:Int) where E: Swift.Error {
        guard let offset:Int = data.firstIndex(of: 0) else {
            throw error(nil)
        }

        let scalars: LazyMapSequence<ArraySlice<UInt8>, Unicode.Scalar> = data[..<offset].lazy.map(Unicode.Scalar.init(_:))

        let name: String = .init(scalars.map(Character.init(_:)))
        guard Self.validate(name: scalars) else {
            throw error(name)
        }

        return (name, offset)
    }

    static func validate<C>(name scalars: C) -> Bool where C: Collection, C.Element == Unicode.Scalar {
        // `count` in range `1 ... 80`
        guard var previous: Unicode.Scalar = scalars.first, scalars.count <= 80 else {
            return false
        }

        for scalar: Unicode.Scalar in scalars {
            guard "\u{20}" ... "\u{7d}" ~= scalar || "\u{a1}" ... "\u{ff}" ~= scalar,
                // no multiple spaces, also checks for no leading spaces
                (previous, scalar) != (" ", " ")
            else {
                return false
            }

            previous = scalar
        }
        // no trailing spaces
        return previous != " "
    }

    private static func language<E>(
        parsing data: ArraySlice<UInt8>,
        else error: (String?) -> E
    ) throws -> (language: [String], offset: Int) where E: Swift.Error {
        guard let offset = data.firstIndex(of: 0) else {
            throw error(nil)
        }

        // check for empty language tag
        guard offset > data.startIndex else {
            return ([], offset)
        }

        // split on '-'
        let language: [String] = try data[..<offset].split(separator: 0x2d, omittingEmptySubsequences: false).map {
            let scalars: LazyMapSequence<ArraySlice<UInt8>, Unicode.Scalar> = $0.lazy.map(Unicode.Scalar.init(_:))
            let tag: String = .init(scalars.map(Character.init(_:)))
            guard Self.validate(language: scalars) else {
                throw error(tag)
            }

            // canonical lowercase
            return tag.lowercased()
        }

        return (language, offset)
    }

    private static func validate<C>(language scalars: C) -> Bool where C: Collection, C.Element == Unicode.Scalar {
        guard 1 ... 8 ~= scalars.count else {
            return false
        }

        return scalars.allSatisfy{ "a" ... "z" ~= $0 || "A" ... "Z" ~= $0 }
    }
}

extension PNGMetadata.Text: CustomStringConvertible {
    var description: String {
        """
        PNG.\(Self.self) (\(PNGChunkIdentifier.tEXt) | \(PNGChunkIdentifier.zTXt) | \(PNGChunkIdentifier.iTXt))
        {
            compressed: \(self.compressed)
            language: '\(self.language.joined(separator: "-"))'
            keyword: '\(self.keyword.english)', '\(self.keyword.localized)'
            content: \"\(self.content)\"
        }
        """
    }
}
