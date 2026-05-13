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

    enum NumberOutcome: Equatable {
        case parsed(Double)
        /// Draft was emptied while the cue currently has a number — clear the
        /// cell. (Empty draft + already-nil number is `.noChange` instead.)
        case cleared
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

    static func commitCueNumber(draft: String, current: Double?) -> NumberOutcome {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return current == nil ? .noChange : .cleared
        }
        let canonical = current.map(FadeTime.formatNumber) ?? ""
        guard let parsed = Double(trimmed), parsed.isFinite else {
            return .revert(canonical: canonical)
        }
        if parsed == current {
            return .noChange
        }
        return .parsed(parsed)
    }
}
