import NIOFileSystem
import Subprocess

#if canImport(System)
import System
public typealias _FilePath = System.FilePath
#else
import SystemPackage
public typealias _FilePath = SystemPackage.FilePath
#endif

public enum CompressionLevel: String {
    case screen = "/screen"
    case ebook = "/ebook"
    case printer = "/printer"
    case prepress = "/prepress"
    case `default` = "/default"
}
public func compressPDF(
    inputFile: _FilePath,
    outputFile: _FilePath,
    compressionLevel: CompressionLevel = .default,
    executablePath: _FilePath? = nil
) async throws {
    let executable: Executable
    if let executablePath {
        executable = .path(executablePath.appending("gs"))
    } else {
        executable = .name("gs")
    }
    let result = try await run(executable, arguments: [
        "-q", "-dBATCH", "-dNOPAUSE", "-sDEVICE=pdfwrite",
        "-dCompatibilityLevel=1.5", "-dColorConversionStrategy=/LeaveColorUnchanged",
        "-dPDFSETTINGS=\(compressionLevel.rawValue)", "-dEmbedAllFonts=true", "-dSubsetFonts=true",
        "-dAutoRotatePages=/None", "-dColorImageDownsampleType=/Bicubic",
        "-dGrayImageDownsampleType=/Bicubic", "-dMonoImageDownsampleType=/Subsample",
        "-dGrayImageResolution=72", "-dColorImageResolution=72", "-dMonoImageResolution=72",
        "-sOutputFile=\(outputFile)", inputFile.string
    ]) { _ in }
    switch result.terminationStatus {
    case .exited(.zero):
        return
    case .exited(let code), .unhandledException(let code):
        throw PDFCompressionError.compressionFailed(code: numericCast(code))
    }
}

enum PDFCompressionError: Error {
    case compressionFailed(code: Int)
}
