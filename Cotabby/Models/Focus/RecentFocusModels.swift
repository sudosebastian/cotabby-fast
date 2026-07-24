import Foundation

/// File overview:
/// A short ring of recently focused writing surfaces. Used only as a **ranking prior** for screen
/// and memory retrieval — never dumped wholesale into the LLM prompt. Knowing the user just left
/// Notion or a PR title is enough to boost those OCR lines without spending the token budget.

/// One previously focused window/app surface.
struct RecentFocusEntry: Equatable, Sendable {
    let bundleIdentifier: String?
    let applicationName: String
    let windowTitle: String?
    let focusedURLString: String?
    let recordedAt: Date

    /// Stable identity for de-duplicating consecutive polls of the same surface.
    var identityKey: String {
        [
            bundleIdentifier ?? "",
            applicationName,
            windowTitle ?? "",
            focusedURLString ?? ""
        ].joined(separator: "\u{1f}")
    }
}
