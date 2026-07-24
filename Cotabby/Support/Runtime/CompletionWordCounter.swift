import Foundation

/// Incremental word counter for decode-time early stop. Scans only the latest piece, so the
/// per-token cost stays O(piece) instead of rescanning the full accumulated completion.
///
/// A "word" starts on a transition into a letter/number run. That matches the English-oriented
/// length presets Cotabby ships (4–7 / 7–12 / …) without depending on whitespace tokenization,
/// which would miscount hyphenated and apostrophe-containing tokens.
nonisolated struct CompletionWordCounter: Equatable, Sendable {
    private(set) var wordCount = 0
    private(set) var isInsideWord = false

    /// How many new words `piece` would start if applied to the current state, without mutating.
    func wordsStarted(by piece: String) -> Int {
        var started = 0
        var inside = isInsideWord
        for character in piece {
            let isWord = Self.isWordCharacter(character)
            if isWord, !inside {
                started += 1
            }
            inside = isWord
        }
        return started
    }

    /// Applies `piece` to the running count.
    mutating func apply(_ piece: String) {
        for character in piece {
            let isWord = Self.isWordCharacter(character)
            if isWord, !isInsideWord {
                wordCount += 1
            }
            isInsideWord = isWord
        }
    }

    /// True when applying `piece` would start a word beyond `maximumWords`. Continuations of the
    /// current word (e.g. the "ing" of "running") are allowed even at the limit.
    func wouldExceedLimit(applying piece: String, maximumWords: Int) -> Bool {
        wordCount + wordsStarted(by: piece) > maximumWords
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
