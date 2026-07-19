import Foundation

/// Uploads generated XML into the console's `gma2/importexport/` over its
/// built-in FTP server (#683). FTP is long-deprecated in Foundation, so the
/// transfer shells out to system `curl`; the testable surface is the pure
/// argument assembly.
enum MA2FTPUploader {

    static let curlPath = "/usr/bin/curl"

    enum Failure: Error, Equatable {
        case uploadFailed(filename: String, message: String)
    }

    static func curlArguments(host: String, filename: String, localFileURL: URL) -> [String] {
        fatalError("unimplemented")
    }

    /// Writes `xml` to a temporary file and uploads it as
    /// `gma2/importexport/<filename>` on `host`.
    static func upload(xml: String, filename: String, host: String) async throws {
        fatalError("unimplemented")
    }
}
