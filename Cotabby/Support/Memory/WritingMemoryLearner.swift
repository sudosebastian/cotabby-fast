import Foundation

/// File overview:
/// Pure learning rules for writing memory. Extracts rare proper-noun-like tokens and short accepted
/// n-grams from Tab-accepted text. Deliberately ignores common stop words so the glossary stays
/// small and useful — stuffing frequent words into the prompt would only add latency.
///
/// Owned by `WritingMemoryStore` at record time; unit-tested without persistence or MainActor.

enum WritingMemoryLearner {
    /// Words that never belong in a personal glossary. Keeping this list short and English-biased
    /// is fine: the rarity gate (capitalization / mixed alnum) still admits domain terms in other
    /// languages when they look distinctive.
    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "then", "else", "when", "while", "for", "to",
        "of", "in", "on", "at", "by", "with", "from", "as", "is", "are", "was", "were", "be", "been",
        "being", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should",
        "may", "might", "must", "can", "this", "that", "these", "those", "it", "its", "i", "you",
        "he", "she", "we", "they", "me", "him", "her", "us", "them", "my", "your", "our", "their",
        "not", "no", "yes", "so", "than", "too", "very", "just", "about", "into", "over", "after",
        "before", "between", "out", "up", "down", "off", "again", "further", "once", "here", "there",
        "all", "any", "both", "each", "few", "more", "most", "other", "some", "such", "only", "own",
        "same", "than", "too", "very", "s", "t", "don", "now", "new", "also", "like", "get", "got"
    ]

    private static let minRareTermLength = 3
    private static let maxRareTermLength = 48
    private static let minNgramWords = 2
    private static let maxNgramWords = 5
    private static let maxNgramsPerAccept = 6
    private static let maxRareTermsPerAccept = 8

    /// Learns glossary terms and n-grams from one accepted chunk. Returns candidate entries with
    /// frequency 1 and `lastUsedAt` set to `now` for the store to merge.
    static func candidates(
        from acceptedText: String,
        bundleIdentifier: String?,
        now: Date = Date()
    ) -> [WritingMemoryEntry] {
        let tokens = tokenize(acceptedText)
        guard !tokens.isEmpty else { return [] }

        var results: [WritingMemoryEntry] = []
        var seenKeys = Set<String>()

        func append(_ entry: WritingMemoryEntry) {
            let key = entry.normalizedKey
            guard !seenKeys.contains(key) else { return }
            seenKeys.insert(key)
            results.append(entry)
        }

        for term in rareTerms(from: tokens).prefix(maxRareTermsPerAccept) {
            append(
                WritingMemoryEntry(
                    text: term,
                    kind: .rareTerm,
                    frequency: 1,
                    lastUsedAt: now,
                    bundleIdentifier: bundleIdentifier
                )
            )
        }

        for phrase in ngrams(from: tokens).prefix(maxNgramsPerAccept) {
            append(
                WritingMemoryEntry(
                    text: phrase,
                    kind: .ngram,
                    frequency: 1,
                    lastUsedAt: now,
                    bundleIdentifier: bundleIdentifier
                )
            )
        }

        return results
    }

    /// Tokenizes on whitespace and strips common trailing punctuation without destroying internals
    /// of identifiers like `cotabby-fast` or `APIKey`.
    static func tokenize(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { raw in
                var token = String(raw)
                while let last = token.last, Self.isBoundaryPunctuation(last) {
                    token.removeLast()
                }
                while let first = token.first, Self.isBoundaryPunctuation(first) {
                    token.removeFirst()
                }
                return token
            }
            .filter { !$0.isEmpty }
    }

    private static func isBoundaryPunctuation(_ character: Character) -> Bool {
        ".,;:!?\"'()[]{}<>".contains(character)
    }

    private static func rareTerms(from tokens: [String]) -> [String] {
        tokens.compactMap { token -> String? in
            let lower = token.lowercased()
            guard token.count >= minRareTermLength, token.count <= maxRareTermLength else {
                return nil
            }
            guard !stopWords.contains(lower) else { return nil }
            guard looksRare(token) else { return nil }
            return token
        }
    }

    /// Prefer capitalized words, mixedCase / snake identifiers, and alphanumeric compounds — the
    /// kinds of tokens a base model is least likely to invent correctly without a glossary.
    private static func looksRare(_ token: String) -> Bool {
        if token.contains(where: { $0.isNumber }) { return true }
        if token.contains("-") || token.contains("_") { return true }
        let letters = token.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        let uppercase = letters.filter(\.isUppercase).count
        if uppercase > 0, uppercase < letters.count { return true }
        if let first = token.first, first.isUppercase, token.count >= 4 { return true }
        // Long lowercase tokens with mixed scripts or uncommon shape still qualify if not stop words
        // and length suggests a name/domain term.
        return token.count >= 8 && token.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func ngrams(from tokens: [String]) -> [String] {
        guard tokens.count >= minNgramWords else { return [] }
        var phrases: [String] = []
        for size in minNgramWords...min(maxNgramWords, tokens.count) {
            for start in 0...(tokens.count - size) {
                let slice = Array(tokens[start..<(start + size)])
                // Skip n-grams that are entirely stop words.
                let content = slice.filter { !stopWords.contains($0.lowercased()) }
                guard !content.isEmpty else { continue }
                phrases.append(slice.joined(separator: " "))
            }
        }
        return phrases
    }
}
