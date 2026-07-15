import Foundation

enum MediaKind: String, Codable {
    case audio
    case video
}

struct MediaReference: Codable, Equatable {
    var displayName: String
    var kind: MediaKind
    var duration: TimeInterval
    var bookmarkData: Data
    /// Set only inside an exported bundle's `.cuelist` (#640): the media file's
    /// path relative to the `.cuelist`, e.g. `"media/Intro.wav"`. Optional and
    /// encoded with `encodeIfPresent`, so a normal working `.cuelist` omits the
    /// key entirely — its plaintext JSON is unchanged (the encrypted envelope
    /// already re-randomises its nonce every save). Authoritative fallback the
    /// open end (#641) uses to auto-attach without a relink.
    var bundlePath: String?

    init(
        displayName: String,
        kind: MediaKind,
        duration: TimeInterval,
        bookmarkData: Data,
        bundlePath: String? = nil
    ) {
        self.displayName = displayName
        self.kind = kind
        self.duration = duration
        self.bookmarkData = bookmarkData
        self.bundlePath = bundlePath
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, kind, duration, bookmarkData, bundlePath
    }

    // Custom encode so a nil `bundlePath` is omitted (synthesized encoding would
    // emit `"bundlePath": null` and perturb every existing file). `Decodable`
    // stays synthesized — a missing optional key decodes to nil.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(kind, forKey: .kind)
        try container.encode(duration, forKey: .duration)
        try container.encode(bookmarkData, forKey: .bookmarkData)
        try container.encodeIfPresent(bundlePath, forKey: .bundlePath)
    }
}
