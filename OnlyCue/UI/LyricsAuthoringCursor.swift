import Foundation

/// Tracks the next-up line in the unplaced queue, by `LyricLine.ID`. Placing a
/// line removes it from `Lyrics.unplacedLines`, so the cursor must follow
/// identity, not a position. UI working state — never persisted.
struct LyricsAuthoringCursor: Equatable {

    /// The explicitly-chosen next-up line, or `nil` to mean "the first unplaced
    /// line." The inspector queue sets this when the user clicks a row.
    private(set) var cursorID: LyricLine.ID?

    init(cursorID: LyricLine.ID? = nil) {
        self.cursorID = cursorID
    }

    /// The line a placement gesture will target, given the current queue.
    /// Honours `cursorID` when it still names an unplaced line; otherwise falls
    /// back to the first unplaced line. `nil` when the queue is empty.
    func resolvedCursorID(unplaced: [LyricLine]) -> LyricLine.ID? {
        if let cursorID, unplaced.contains(where: { $0.id == cursorID }) {
            return cursorID
        }
        return unplaced.first?.id
    }

    /// Advances the cursor after `placedID` left the queue. Points at the first
    /// remaining unplaced line, or `nil` when the queue is now empty.
    mutating func advance(afterPlacing placedID: LyricLine.ID, remainingUnplaced: [LyricLine]) {
        cursorID = remainingUnplaced.first?.id
    }

    /// Explicitly selects a queue line as next-up (inspector click).
    mutating func select(_ id: LyricLine.ID?) {
        cursorID = id
    }
}
