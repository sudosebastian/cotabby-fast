import Foundation

/// File overview:
/// Domain values for Cotabby's local writing memory: rare terms and accepted n-grams learned from
/// Tab accepts (and optionally high-confidence OCR). Kept separate from SymSpell frequency
/// dictionaries, which rank typo corrections and must not steer completions.

/// One learned writing unit: either a rare term (glossary) or a multi-word phrase (n-gram).
struct WritingMemoryEntry: Equatable, Sendable, Codable {
    enum Kind: String, Equatable, Sendable, Codable {
        case rareTerm
        case ngram
    }

    let text: String
    let kind: Kind
    var frequency: Int
    var lastUsedAt: Date
    /// Optional bundle affinity so Slack jargon ranks higher while focusing Slack.
    var bundleIdentifier: String?

    var normalizedKey: String {
        text.lowercased()
    }
}

/// Immutable snapshot handed to pure retrievers between keystrokes.
struct WritingMemorySnapshot: Equatable, Sendable {
    let entries: [WritingMemoryEntry]

    static let empty = WritingMemorySnapshot(entries: [])
}
