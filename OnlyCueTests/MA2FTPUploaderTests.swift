import XCTest
@testable import OnlyCue

/// #683 — XML files reach the console via its built-in FTP server
/// (`data`/`data`, exposes the gma2 folder). Upload runs through system `curl`
/// (FTP is long-deprecated in Foundation); the testable surface is the pure
/// argument assembly, not a live transfer.
final class MA2FTPUploaderTests: XCTestCase {

    func test_curlArguments_targetImportExportFolder_withDataCredentials() {
        let arguments = MA2FTPUploader.curlArguments(
            host: "192.168.0.10",
            filename: "onlycue_seq_18.xml",
            localFileURL: URL(fileURLWithPath: "/tmp/onlycue_seq_18.xml")
        )
        XCTAssertEqual(arguments, [
            "--silent",
            "--show-error",
            "--connect-timeout", "5",
            "--user", "data:data",
            "--upload-file", "/tmp/onlycue_seq_18.xml",
            "ftp://192.168.0.10/gma2/importexport/onlycue_seq_18.xml"
        ])
    }

    func test_curlArguments_percentEncodesFilename() {
        // Filenames are slot-stamped and safe today, but a URL must stay a URL.
        let arguments = MA2FTPUploader.curlArguments(
            host: "10.0.0.2",
            filename: "a b.xml",
            localFileURL: URL(fileURLWithPath: "/tmp/a b.xml")
        )
        XCTAssertEqual(arguments.last, "ftp://10.0.0.2/gma2/importexport/a%20b.xml")
    }

    func test_curlLaunchPath_isSystemCurl() {
        XCTAssertEqual(MA2FTPUploader.curlPath, "/usr/bin/curl")
    }
}
