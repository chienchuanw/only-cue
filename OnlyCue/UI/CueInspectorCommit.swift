import Foundation

/// Pure logic for inspector field commits. The inspector view never embeds the
/// parse-or-revert decision tree itself — it asks this helper and acts on the
/// result. Lets us TDD the behavior without spinning up a SwiftUI host.
enum CueInspectorCommit {

    enum FadeOutcome: Equatable {
        case parsed(FadeTime)
        case noChange
        case revert(canonical: String)
    }

    static func commitFadeTime(draft: String, current: FadeTime) -> FadeOutcome {
        guard let parsed = FadeTime.parse(draft) else {
            return .revert(canonical: current.format())
        }
        if parsed == current {
            return .noChange
        }
        return .parsed(parsed)
    }
}
