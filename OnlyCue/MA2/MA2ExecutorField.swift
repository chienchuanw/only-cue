import Foundation

/// Parses the batch sheet's per-song executor text field (#765). `"page.number"` → an
/// assigned executor; blank/whitespace → unassigned (#764). Anything malformed (missing dot,
/// non-numeric, non-positive) is treated as unassigned so a typo never emits an invalid
/// `At Exec` — the pre-flight surfaces a half-typed value as unassigned rather than crashing.
enum MA2ExecutorField {

    static func parse(_ text: String) -> (page: Int, number: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let page = Int(parts[0]), let number = Int(parts[1]),
              page >= 1, number >= 1 else { return nil }
        return (page, number)
    }

    /// The field text for a target's executor: `"page.number"` or empty when unassigned.
    static func text(page: Int?, number: Int?) -> String {
        guard let page, let number else { return "" }
        return "\(page).\(number)"
    }
}
