import Foundation

/// File overview:
/// Pure ranking over field OCR, ambient screen lines, writing memory, and recent focus. Produces the
/// bounded `RetrievedPromptContext` that request construction injects. Lives in Support so it can be
/// unit-tested without ScreenCaptureKit, Vision, or MainActor stores.
///
/// Design invariant: never return more text than the prompt budgets can absorb. The LLM does not
/// "look up" a dictionary — it conditions on text — so retrieval quality matters more than volume.
///
/// When `queryEmbedding` is present and ambient lines carry unit vectors from
/// `TextSemanticEmbedder`, screen ranking blends cosine similarity on top of lexical overlap so
/// related-but-token-disjoint OCR lines can still surface. Embedding work itself never happens here.

enum ContextualRetriever {
    /// Soft cap for the screen section before the renderer’s tighter per-section max (280).
    static let maxScreenCharacters = 400
    /// Soft cap for the memory glossary section (renderer max ~240).
    static let maxGlossaryCharacters = 240
    static let maxScreenSnippets = 6
    static let maxGlossaryTerms = 8

    /// Assembles prompt-ready context. `fieldOCR` is the existing once-per-field excerpt; ambient
    /// lines come from the background multi-display index; memory from Tab accepts.
    /// `queryEmbedding` is an optional unit vector for the caret prefix tip; when nil, ranking
    /// stays purely lexical (the pre-embedder behavior).
    static func retrieve(
        prefixText: String,
        fieldOCR: String?,
        ambientLines: [ScreenTextIndexLine],
        memory: WritingMemorySnapshot,
        recentFocus: [RecentFocusEntry],
        currentBundleIdentifier: String?,
        queryEmbedding: [Float]? = nil
    ) -> RetrievedPromptContext {
        let prefixTokens = Set(WritingMemoryLearner.tokenize(prefixText).map { $0.lowercased() })

        let screenSummary = rankScreen(
            prefixTokens: prefixTokens,
            fieldOCR: fieldOCR,
            ambientLines: ambientLines,
            recentFocus: recentFocus,
            queryEmbedding: queryEmbedding
        )

        let glossary = rankGlossary(
            prefixTokens: prefixTokens,
            memory: memory,
            currentBundleIdentifier: currentBundleIdentifier
        )

        let instant = instantContinuation(prefixText: prefixText, memory: memory)

        return RetrievedPromptContext(
            screenSummary: screenSummary,
            memoryGlossary: glossary,
            instantContinuation: instant
        )
    }

    // MARK: - Screen

    private static func rankScreen(
        prefixTokens: Set<String>,
        fieldOCR: String?,
        ambientLines: [ScreenTextIndexLine],
        recentFocus: [RecentFocusEntry],
        queryEmbedding: [Float]?
    ) -> String? {
        var scored: [RetrievedContextSnippet] = []
        let recentTitles = recentFocus.compactMap(\.windowTitle)

        if let fieldOCR {
            let cleaned = fieldOCR.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                let overlap = tokenOverlap(prefixTokens, in: cleaned)
                scored.append(
                    RetrievedContextSnippet(
                        text: cleaned,
                        source: .fieldOCR,
                        score: 1.0 + Double(overlap) * 0.35
                    )
                )
            }
        }

        for line in ambientLines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 4 else { continue }
            let overlap = tokenOverlap(prefixTokens, in: text)
            var score = Double(line.confidence) * 0.5 + Double(overlap) * 0.8
            if let hint = line.windowHint,
               recentTitles.contains(where: { title in
                   title.localizedCaseInsensitiveContains(hint) || hint.localizedCaseInsensitiveContains(title)
               }) {
                score += 0.4
            }
            // Recency of capture: prefer fresher ambient lines slightly.
            let age = Date().timeIntervalSince(line.capturedAt)
            score += max(0, 0.3 - age / 60.0)
            // Semantic boost: related lines without shared tokens (schedule ↔ calendar).
            if let queryEmbedding, let lineEmbedding = line.embedding {
                let cosine = TextSemanticEmbedder.cosineSimilarity(queryEmbedding, lineEmbedding)
                let excess = max(0, Double(cosine - TextSemanticEmbedder.semanticFloor))
                score += excess * TextSemanticEmbedder.semanticWeight
            }
            scored.append(
                RetrievedContextSnippet(text: text, source: .ambientScreen, score: score)
            )
        }

        // Recent focus titles as light cues when they overlap the prefix.
        for entry in recentFocus.prefix(4) {
            guard let title = entry.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  title.count >= 4 else { continue }
            let overlap = tokenOverlap(prefixTokens, in: title)
            guard overlap > 0 else { continue }
            scored.append(
                RetrievedContextSnippet(
                    text: title,
                    source: .recentFocus,
                    score: 0.55 + Double(overlap) * 0.4
                )
            )
        }

        scored.sort { $0.score > $1.score }

        var pieces: [String] = []
        var used = Set<String>()
        var total = 0

        // Field OCR is the precise once-per-focus crop — always keep it when present, then fill
        // remaining budget with ranked ambient / focus titles. Otherwise prefix-overlapping ambient
        // lines can crowd out the nearby-field text entirely.
        for snippet in scored where snippet.source == .fieldOCR {
            let next = snippet.text
            used.insert(next.lowercased())
            pieces.append(next)
            total += next.count + 2
            break
        }

        for snippet in scored {
            let key = snippet.text.lowercased()
            guard !used.contains(key) else { continue }
            // Drop ambient lines that are near-duplicates of field OCR already kept.
            if snippet.source == .ambientScreen,
               pieces.contains(where: { $0.localizedCaseInsensitiveContains(snippet.text) || snippet.text.localizedCaseInsensitiveContains($0) }) {
                continue
            }
            let next = snippet.text
            if total + next.count + 2 > maxScreenCharacters { break }
            used.insert(key)
            pieces.append(next)
            total += next.count + 2
            if pieces.count >= maxScreenSnippets { break }
        }

        guard !pieces.isEmpty else { return nil }
        return pieces.joined(separator: " · ")
    }

    // MARK: - Glossary

    private static func rankGlossary(
        prefixTokens: Set<String>,
        memory: WritingMemorySnapshot,
        currentBundleIdentifier: String?
    ) -> String? {
        let rareTerms = memory.entries.filter { $0.kind == .rareTerm }
        guard !rareTerms.isEmpty else { return nil }

        let scored = rareTerms.map { entry -> (WritingMemoryEntry, Double) in
            var score = Double(entry.frequency)
            let ageHours = Date().timeIntervalSince(entry.lastUsedAt) / 3600
            score *= max(0.2, 1.0 - ageHours / 720.0) // decay over ~30 days
            if let bundle = entry.bundleIdentifier, bundle == currentBundleIdentifier {
                score *= 1.4
            }
            let keyTokens = Set(WritingMemoryLearner.tokenize(entry.text).map { $0.lowercased() })
            if !prefixTokens.isDisjoint(with: keyTokens) {
                score *= 2.0
            } else if prefixTokens.contains(where: { token in
                keyTokens.contains(where: { $0.hasPrefix(token) && token.count >= 2 })
            }) {
                score *= 1.5
            }
            return (entry, score)
        }
        .sorted { $0.1 > $1.1 }

        var terms: [String] = []
        var total = 0
        for (entry, _) in scored {
            let text = entry.text
            if total + text.count + 2 > maxGlossaryCharacters { break }
            if terms.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
                continue
            }
            let keyTokens = Set(WritingMemoryLearner.tokenize(text).map { $0.lowercased() })
            // With a live prefix, only inject terms that share tokens or a typed stem. Without a
            // prefix (rare), fall back to the top-scoring rare terms so a cold field still gets a
            // tiny glossary.
            let relevant: Bool
            if prefixTokens.isEmpty {
                relevant = true
            } else {
                relevant = !prefixTokens.isDisjoint(with: keyTokens)
                    || prefixTokens.contains(where: { token in
                        keyTokens.contains(where: { $0.hasPrefix(token) && token.count >= 2 })
                    })
            }
            guard relevant else { continue }
            terms.append(text)
            total += text.count + 2
            if terms.count >= maxGlossaryTerms { break }
        }

        guard !terms.isEmpty else { return nil }
        return terms.joined(separator: ", ")
    }

    // MARK: - Instant continuation

    /// Returns an n-gram continuation when the caret prefix uniquely ends with the start of a
    /// frequently accepted phrase. High bar: avoids surprising the user with wrong memory hits.
    static func instantContinuation(
        prefixText: String,
        memory: WritingMemorySnapshot
    ) -> String? {
        let trimmed = prefixText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        let ngrams = memory.entries
            .filter { $0.kind == .ngram && $0.frequency >= 2 }
            .sorted { lhs, rhs in
                if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
                return lhs.lastUsedAt > rhs.lastUsedAt
            }

        var best: (remainder: String, frequency: Int)?
        for entry in ngrams {
            let phrase = entry.text
            // Match when prefix ends with the start of the phrase (case-insensitive), and there is
            // a non-empty remainder to insert.
            guard let remainder = continuationRemainder(prefix: trimmed, phrase: phrase),
                  !remainder.isEmpty else { continue }
            if let current = best {
                if entry.frequency > current.frequency {
                    best = (remainder, entry.frequency)
                }
            } else {
                best = (remainder, entry.frequency)
            }
        }

        // Require a clear winner: at least frequency 2 (already filtered) and no second candidate
        // with the same frequency and a different remainder in the top set — uniqueness check.
        guard let best else { return nil }
        let competing = ngrams.filter { entry in
            guard let remainder = continuationRemainder(prefix: trimmed, phrase: entry.text) else {
                return false
            }
            return remainder != best.remainder && entry.frequency >= best.frequency
        }
        guard competing.isEmpty else { return nil }
        return best.remainder
    }

    /// If `prefix` ends with a case-insensitive prefix of `phrase`, return the leftover phrase tail
    /// (including a leading space when the match ended on a word boundary inside the phrase).
    private static func continuationRemainder(prefix: String, phrase: String) -> String? {
        let prefixLower = prefix.lowercased()
        let phraseLower = phrase.lowercased()

        // Try matching the longest phrase-prefix that is a suffix of the caret prefix.
        let phraseWords = phrase.split(separator: " ").map(String.init)
        guard phraseWords.count >= 2 else { return nil }

        for take in 1..<phraseWords.count {
            let head = phraseWords.prefix(take).joined(separator: " ")
            let headLower = head.lowercased()
            guard prefixLower.hasSuffix(headLower) || prefixLower.hasSuffix(" " + headLower) else {
                continue
            }
            // Ensure we matched on a boundary: either start of prefix or preceded by whitespace.
            let matchLength = headLower.count
            let start = prefixLower.index(prefixLower.endIndex, offsetBy: -matchLength)
            if start != prefixLower.startIndex {
                let before = prefixLower[prefixLower.index(before: start)]
                guard before.isWhitespace else { continue }
            }
            let rest = phraseWords.suffix(from: take).joined(separator: " ")
            // Preserve a leading space when the prefix does not already end with whitespace and the
            // matched head did not consume a trailing space from the field.
            if prefix.hasSuffix(" ") || prefix.hasSuffix(head) && prefix.lowercased().hasSuffix(headLower) {
                let needsSpace = !prefix.hasSuffix(" ") && !prefix.hasSuffix("\n")
                return needsSpace ? " " + rest : rest
            }
            return " " + rest
        }

        // Also allow matching the whole phrase start as a partial last token ("Cotab" → "by").
        if let first = phraseWords.first {
            let firstLower = first.lowercased()
            guard firstLower.count >= 3 else { return nil }
            // Last token of prefix.
            let lastToken = WritingMemoryLearner.tokenize(prefix).last?.lowercased() ?? ""
            guard !lastToken.isEmpty, firstLower.hasPrefix(lastToken), firstLower != lastToken else {
                return nil
            }
            let completedFirst = String(first.dropFirst(lastToken.count))
            let restWords = phraseWords.dropFirst()
            if restWords.isEmpty {
                return completedFirst
            }
            return completedFirst + " " + restWords.joined(separator: " ")
        }

        return nil
    }

    private static func tokenOverlap(_ prefixTokens: Set<String>, in text: String) -> Int {
        guard !prefixTokens.isEmpty else { return 0 }
        let textTokens = Set(WritingMemoryLearner.tokenize(text).map { $0.lowercased() })
        return prefixTokens.intersection(textTokens).count
    }
}
