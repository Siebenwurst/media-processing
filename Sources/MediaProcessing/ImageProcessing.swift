import NIOFileSystem
import Subprocess
import Synchronization
import Logging
import RegexBuilder

public struct ImageProcessor: Sendable {

    private let fileSystem: FileSystem
    private let logger: Logger
    private let executablePath: _FilePath?

    public init(fileSystem: FileSystem = .shared, logger: Logger = Logger(label: "ImageProcessor"), executablePath: _FilePath? = nil) {
        self.fileSystem = fileSystem
        self.logger = logger
        self.executablePath = executablePath
    }

    public func compressImage(inputFile: _FilePath, size: Int, format: String? = nil) async throws -> (FilePath, width: Int, height: Int) {
        let (filePath, filePathWildcard) = makePaths(for: inputFile, format: format)

        let thumbnailExecutable: Executable
        if let executablePath {
            thumbnailExecutable = .path(executablePath.appending("vipsthumbnail"))
        } else {
            thumbnailExecutable = .name("vipsthumbnail")
        }
        let thumbnailExecutionResult = try await run(
            thumbnailExecutable,
            arguments: ["-s", "\(size)", "--no-rotate", inputFile.string, "-o", filePathWildcard.string]
        ) { _ in }
        switch thumbnailExecutionResult.terminationStatus {
        case .exited(0):
            break
        case .exited(let code), .unhandledException(let code):
            throw ImageCompressionError.compressionFailed(code: numericCast(code))
        }

        let headersExecutable: Executable
        if let executablePath {
            headersExecutable = .path(executablePath.appending("vipsheader"))
        } else {
            headersExecutable = .name("vipsheader")
        }
        let headersExecutionResult = try await run(headersExecutable, arguments: ["-a", filePath.string]) { (execution: Execution, standardOutput: AsyncBufferSequence) -> (Int?, Int?) in
            var width: Int?
            var height: Int?
            for try await line in standardOutput.lines(encoding: UTF8.self) {
                if line.starts(with: "width:") {
                    width = parseDimension(from: line)
                } else if line.starts(with: "height:") {
                    height = parseDimension(from: line)
                }
            }
            return (width, height)
        }

        let width: Int
        let height: Int

        if let w = headersExecutionResult.value.0, let h = headersExecutionResult.value.1 {
            width = w
            height = h
        } else {
            logger.warning("Couldn't determine image dimensions for \(filePath)")
            (width, height) = (0, 0)
        }

        return (.init(filePath.string), width, height)
    }

    public enum ThumbHashFormat {
        case raw
        case hex
        case base64
    }
    public enum ThumbHashResult {
        case raw([UInt8])
        case hex([String])
        case base64(String)
    }
    public func thumbHash(for image: _FilePath, format: ThumbHashFormat = .raw) async throws -> ThumbHashResult {
        let (filePath, width, height) = try await compressImage(inputFile: image, size: 100, format: "png")
        let raw = try await fileSystem.withFileHandle(forReadingAt: filePath) { read in
            let sequence = read.readChunks(chunkLength: .bytes(1))
                .map { $0.getInteger(at: $0.readerIndex, as: UInt8.self).unsafelyUnwrapped }
            return try await PNGImage.decode(from: sequence).unpack(as: RGBA<UInt8>.self)
        }

        let hash = rgbaToThumbHash(width: width, height: height, rgba: raw.flatMap({ [$0.r, $0.g, $0.b, $0.a] }))
        print("raw hash:", hash)
        print("hex hash:", hash.map({
            let raw = String($0, radix: 16, uppercase: true)
            if raw.count == 1 {
                return "0" + raw
            }
            return raw
        }).joined(separator: " "))
        switch format {
        case .raw:
            return .raw(hash)
        case .hex:
            return .hex(hash.map {
                let raw = String($0, radix: 16, uppercase: true)
                if raw.count == 1 {
                    return "0" + raw
                }
                return raw
            })
        case .base64:
            return .base64(String(_base64Encoding: hash))
        }
    }


    func makePaths(for file: _FilePath, format: String?) -> (filePath: _FilePath, filePathWildcard: _FilePath) {
        let filename = file.lastComponent ?? "img.jpeg"
        let fileParts = file.removingLastComponent()
        let filePath = if let format {
            fileParts.appending("tn_\(filename).\(format)")
        } else {
            fileParts.appending("tn_\(filename)")
        }

        let filePathWildcard = fileParts.appending("tn_%s.\(format ?? filename.extension ?? "jpeg")")
        return (filePath, filePathWildcard)
    }

    func parseDimension(from line: String) -> Int? {
        (line.split(separator: ":").last?.replacing(/(^\s+|\s+$)/, with: "")).flatMap { Int($0) }
    }
}

enum ImageCompressionError: Error {
    case compressionFailed(code: Int)
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// This is a simplified vendored version from:
// https://github.com/fabianfett/swift-base64-kit

extension String {
    /// Base64 encode a collection of UInt8 to a string, without the use of Foundation.
    @inlinable
    public init<Buffer: Collection>(_base64Encoding bytes: Buffer) where Buffer.Element == UInt8 {
        self = Base64.encode(bytes: bytes)
    }

    @inlinable
    public func _base64Decoded() throws -> [UInt8] {
        try Base64.decode(string: self)
    }
}

public enum Base64Error: Error {
    case invalidLength
    case invalidCharacter
}

@usableFromInline
internal enum Base64: Sendable {

    @inlinable
    static func encode<Buffer: Collection>(bytes: Buffer) -> String where Buffer.Element == UInt8 {
        guard !bytes.isEmpty else {
            return ""
        }

        // In Base64, 3 bytes become 4 output characters, and we pad to the
        // nearest multiple of four.
        let base64StringLength = ((bytes.count + 2) / 3) * 4
        let alphabet = Base64.encodingTable

        return String(unsafeUninitializedCapacity: base64StringLength) { backingStorage in
            var input = bytes.makeIterator()
            var offset = 0
            while let firstByte = input.next() {
                let secondByte = input.next()
                let thirdByte = input.next()

                backingStorage[offset] = Base64.encode(alphabet: alphabet, firstByte: firstByte)
                backingStorage[offset + 1] = Base64.encode(
                    alphabet: alphabet,
                    firstByte: firstByte,
                    secondByte: secondByte
                )
                backingStorage[offset + 2] = Base64.encode(
                    alphabet: alphabet,
                    secondByte: secondByte,
                    thirdByte: thirdByte
                )
                backingStorage[offset + 3] = Base64.encode(alphabet: alphabet, thirdByte: thirdByte)
                offset += 4
            }
            return offset
        }
    }

    @inlinable
    static func decode(string: String) throws -> [UInt8] {
        guard string.count % 4 == 0 else {
            throw Base64Error.invalidLength
        }

        let bytes = string.utf8.map { $0 }
        var decoded = [UInt8]()

        // Go over the encoded string in groups of 4 characters,
        // and build groups of 3 bytes from them.
        for i in stride(from: 0, to: bytes.count, by: 4) {
            guard let byte0Index = Base64.encodingTable.firstIndex(of: bytes[i]),
                  let byte1Index = Base64.encodingTable.firstIndex(of: bytes[i + 1])
            else {
                throw Base64Error.invalidCharacter
            }

            let byte0 = (UInt8(byte0Index) << 2 | UInt8(byte1Index) >> 4)
            decoded.append(byte0)

            // Check if the 3rd char is not a padding character, and decode the 2nd byte
            if bytes[i + 2] != Base64.encodePaddingCharacter {
                guard let byte2Index = Base64.encodingTable.firstIndex(of: bytes[i + 2]) else {
                    throw Base64Error.invalidCharacter
                }

                let second = (UInt8(byte1Index) << 4 | UInt8(byte2Index) >> 2)
                decoded.append(second)
            }

            // Check if the 4th character is not a padding, and decode the 3rd byte
            if bytes[i + 3] != Base64.encodePaddingCharacter {
                guard let byte3Index = Base64.encodingTable.firstIndex(of: bytes[i + 3]),
                      let byte2Index = Base64.encodingTable.firstIndex(of: bytes[i + 2])
                else {
                    throw Base64Error.invalidCharacter
                }
                let third = (UInt8(byte2Index) << 6 | UInt8(byte3Index))
                decoded.append(third)
            }
        }
        return decoded
    }

    // MARK: Internal

    // The base64 unicode table.
    @usableFromInline
    static let encodingTable: [UInt8] = [
        UInt8(ascii: "A"), UInt8(ascii: "B"), UInt8(ascii: "C"), UInt8(ascii: "D"),
        UInt8(ascii: "E"), UInt8(ascii: "F"), UInt8(ascii: "G"), UInt8(ascii: "H"),
        UInt8(ascii: "I"), UInt8(ascii: "J"), UInt8(ascii: "K"), UInt8(ascii: "L"),
        UInt8(ascii: "M"), UInt8(ascii: "N"), UInt8(ascii: "O"), UInt8(ascii: "P"),
        UInt8(ascii: "Q"), UInt8(ascii: "R"), UInt8(ascii: "S"), UInt8(ascii: "T"),
        UInt8(ascii: "U"), UInt8(ascii: "V"), UInt8(ascii: "W"), UInt8(ascii: "X"),
        UInt8(ascii: "Y"), UInt8(ascii: "Z"), UInt8(ascii: "a"), UInt8(ascii: "b"),
        UInt8(ascii: "c"), UInt8(ascii: "d"), UInt8(ascii: "e"), UInt8(ascii: "f"),
        UInt8(ascii: "g"), UInt8(ascii: "h"), UInt8(ascii: "i"), UInt8(ascii: "j"),
        UInt8(ascii: "k"), UInt8(ascii: "l"), UInt8(ascii: "m"), UInt8(ascii: "n"),
        UInt8(ascii: "o"), UInt8(ascii: "p"), UInt8(ascii: "q"), UInt8(ascii: "r"),
        UInt8(ascii: "s"), UInt8(ascii: "t"), UInt8(ascii: "u"), UInt8(ascii: "v"),
        UInt8(ascii: "w"), UInt8(ascii: "x"), UInt8(ascii: "y"), UInt8(ascii: "z"),
        UInt8(ascii: "0"), UInt8(ascii: "1"), UInt8(ascii: "2"), UInt8(ascii: "3"),
        UInt8(ascii: "4"), UInt8(ascii: "5"), UInt8(ascii: "6"), UInt8(ascii: "7"),
        UInt8(ascii: "8"), UInt8(ascii: "9"), UInt8(ascii: "+"), UInt8(ascii: "/"),
    ]

    @usableFromInline
    static let encodePaddingCharacter: UInt8 = UInt8(ascii: "=")

    @usableFromInline
    static func encode(alphabet: [UInt8], firstByte: UInt8) -> UInt8 {
        let index = firstByte >> 2
        return alphabet[Int(index)]
    }

    @usableFromInline
    static func encode(alphabet: [UInt8], firstByte: UInt8, secondByte: UInt8?) -> UInt8 {
        var index = (firstByte & 0b00000011) << 4
        if let secondByte = secondByte {
            index += (secondByte & 0b11110000) >> 4
        }
        return alphabet[Int(index)]
    }

    @usableFromInline
    static func encode(alphabet: [UInt8], secondByte: UInt8?, thirdByte: UInt8?) -> UInt8 {
        guard let secondByte = secondByte else {
            // No second byte means we are just emitting padding.
            return Base64.encodePaddingCharacter
        }
        var index = (secondByte & 0b00001111) << 2
        if let thirdByte = thirdByte {
            index += (thirdByte & 0b11000000) >> 6
        }
        return alphabet[Int(index)]
    }

    @usableFromInline
    static func encode(alphabet: [UInt8], thirdByte: UInt8?) -> UInt8 {
        guard let thirdByte = thirdByte else {
            // No third byte means just padding.
            return Base64.encodePaddingCharacter
        }
        let index = thirdByte & 0b00111111
        return alphabet[Int(index)]
    }
}
