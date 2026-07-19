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
        let encodedFilename = filename.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? filename
        return [
            "--silent",
            "--show-error",
            "--connect-timeout", "5",
            "--user", "data:data",
            "--upload-file", localFileURL.path,
            "ftp://\(host)/gma2/importexport/\(encodedFilename)"
        ]
    }

    /// Writes `xml` to a temporary file and uploads it as
    /// `gma2/importexport/<filename>` on `host`.
    static func upload(xml: String, filename: String, host: String) async throws {
        let localFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try xml.write(to: localFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: localFileURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: curlPath)
        process.arguments = curlArguments(host: host, filename: filename, localFileURL: localFileURL)
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        try process.run()
        // `waitUntilExit` blocks its thread; hop it off the cooperative pool.
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(bytes: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw Failure.uploadFailed(
                filename: filename,
                message: message.isEmpty ? "curl exited with status \(process.terminationStatus)" : message
            )
        }
    }
}
