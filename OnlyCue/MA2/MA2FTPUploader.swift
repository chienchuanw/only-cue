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
        // A host containing `/`, `@`, `?` or spaces would silently rewrite the
        // curl URL's path or userinfo — refuse it before any process runs.
        guard !host.isEmpty,
              host.rangeOfCharacter(from: CharacterSet.urlHostAllowed.inverted) == nil,
              !host.contains("/"), !host.contains("@") else {
            throw Failure.uploadFailed(filename: filename, message: "Invalid console host: \"\(host)\"")
        }

        // Unique directory per upload so simultaneous pushes targeting the
        // same slot number cannot race on one temp file.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnlyCue-MA2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFileURL = directory.appendingPathComponent(filename)
        try xml.write(to: localFileURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: curlPath)
        process.arguments = curlArguments(host: host, filename: filename, localFileURL: localFileURL)
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        // `waitUntilExit` blocks its thread; hop it off the cooperative pool.
        // The termination handler must be installed BEFORE `run()` — a fast
        // exit could otherwise slip past and leave the continuation hanging.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
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
