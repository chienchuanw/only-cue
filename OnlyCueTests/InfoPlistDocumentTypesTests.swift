import XCTest

/// #580 — guards the SwiftUI `DocumentGroup` close-review (the "save changes?"
/// sheet). A stray `NSDocumentClass` in `CFBundleDocumentTypes` hands document
/// management to AppKit's `NSDocumentController`, which bypasses that sheet for
/// a `ReferenceFileDocument`, so edits are lost silently on close. This test
/// fails if anyone reintroduces the key.
final class InfoPlistDocumentTypesTests: XCTestCase {

    /// `#filePath` = <repo>/OnlyCueTests/InfoPlistDocumentTypesTests.swift, so
    /// two parents up is the repo root. Reading the source plist directly keeps
    /// the test independent of test-bundle hosting.
    private func infoPlistURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OnlyCue/Resources/Info.plist")
    }

    func test_documentTypes_doNotDeclareNSDocumentClass() throws {
        let data = try Data(contentsOf: infoPlistURL())
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let root = try XCTUnwrap(plist as? [String: Any])
        let documentTypes = (root["CFBundleDocumentTypes"] as? [[String: Any]]) ?? []

        XCTAssertFalse(documentTypes.isEmpty, "Expected CFBundleDocumentTypes to be declared for the .cuelist association")
        for entry in documentTypes {
            XCTAssertNil(
                entry["NSDocumentClass"],
                "CFBundleDocumentTypes must not declare NSDocumentClass — it breaks the DocumentGroup save-on-close review (#580)"
            )
        }
    }
}
