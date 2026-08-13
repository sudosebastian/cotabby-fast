import Accelerate
import Foundation
import NaturalLanguage

/// File overview:
/// Tiny on-device sentence embedder for ambient-screen retrieval. Uses Apple's
/// `NLEmbedding.sentenceEmbedding` (no downloaded GGUF, no second generative model) so related
/// OCR lines can rank above token-overlap misses — e.g. caret prefix "schedule" surfacing a
/// calendar line that shares no tokens.
///
/// Ownership: long-lived singleton used by `AmbientScreenIndexer` (batch fill after OCR) and by
/// `SuggestionCoordinator` (one query vector per retrieve). Ranking math stays in
/// `ContextualRetriever`; this type only produces unit vectors and cosine similarity.
///
/// Critical-path rules:
/// - Batch embedding of the ambient index runs off the main actor during refresh, never while
///   generating a suggestion.
/// - Query embedding is one sentence vector (~a few ms) and is cached for identical prefix tips
///   so rapid keystrokes do not re-embed the same string.
nonisolated final class TextSemanticEmbedder: @unchecked Sendable {
    static let shared = TextSemanticEmbedder()

    /// Ignore caret prefixes shorter than this — sentence embeddings need a little topical mass.
    static let minimumQueryCharacters = 8
    /// Only the trailing tip of the caret prefix is embedded; older buffer text dilutes the topic.
    static let maximumQueryCharacters = 240
    /// Cosine below this is treated as noise and does not boost retrieval scores.
    static let semanticFloor: Float = 0.25
    /// Multiplier applied to `max(0, cosine - floor)` inside `ContextualRetriever`.
    static let semanticWeight: Double = 1.6

    private let lock = NSLock()
    private var sentenceEmbedding: NLEmbedding?
    private var didAttemptLoad = false
    private var queryCache: (key: String, vector: [Float])?

    nonisolated init() {}

    /// Whether the OS sentence embedding model is available for English.
    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadEmbeddingLocked() != nil
    }

    /// Embeds the topical tip of a caret prefix into a unit vector, or `nil` when too short /
    /// unavailable. Results for identical tips are cached.
    func embedQuery(from prefixText: String) -> [Float]? {
        let tip = Self.queryTip(from: prefixText)
        guard tip.count >= Self.minimumQueryCharacters else { return nil }

        lock.lock()
        if let cached = queryCache, cached.key == tip {
            let vector = cached.vector
            lock.unlock()
            return vector
        }
        lock.unlock()

        guard let vector = embed(tip) else { return nil }

        lock.lock()
        queryCache = (tip, vector)
        lock.unlock()
        return vector
    }

    /// Returns a unit-length sentence embedding for `text`, or `nil` when the model cannot encode it.
    func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }

        lock.lock()
        let embedding = loadEmbeddingLocked()
        lock.unlock()
        guard let embedding else { return nil }
        guard let doubles = embedding.vector(for: trimmed), !doubles.isEmpty else { return nil }
        return Self.unitVector(doubles.map { Float($0) })
    }

    /// Attaches unit embeddings to ambient index lines. Runs entirely off-actor-friendly code so
    /// callers can wrap it in `Task.detached` during refresh.
    func embeddingFilled(lines: [ScreenTextIndexLine]) -> [ScreenTextIndexLine] {
        lines.map { line in
            guard line.embedding == nil else { return line }
            let vector = embed(line.text)
            guard let vector else { return line }
            return ScreenTextIndexLine(
                text: line.text,
                displayID: line.displayID,
                confidence: line.confidence,
                capturedAt: line.capturedAt,
                windowHint: line.windowHint,
                embedding: vector
            )
        }
    }

    /// Cosine similarity for two unit vectors. Non-unit inputs still work but are slightly slower
    /// and less accurate; index/query paths always normalize first.
    static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return 0 }
        return vDSP.dot(lhs, rhs)
    }

    /// Trailing tip of the caret prefix used as the retrieval query.
    static func queryTip(from prefixText: String) -> String {
        let trimmed = prefixText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumQueryCharacters else { return trimmed }
        let start = trimmed.index(trimmed.endIndex, offsetBy: -maximumQueryCharacters)
        var tip = String(trimmed[start...])
        // Drop a leading partial word so the tip starts on a boundary when possible.
        if let whitespace = tip.firstIndex(where: { $0.isWhitespace }) {
            let after = tip.index(after: whitespace)
            if after < tip.endIndex {
                tip = String(tip[after...])
            }
        }
        return tip.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private func loadEmbeddingLocked() -> NLEmbedding? {
        if didAttemptLoad {
            return sentenceEmbedding
        }
        didAttemptLoad = true
        // English-first: ambient OCR and autocomplete prefixes in Cotabby are predominantly English.
        // Non-English prefixes simply omit the semantic boost and keep lexical ranking.
        sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        return sentenceEmbedding
    }

    private static func unitVector(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty else { return nil }
        var mutable = vector
        let norm = vDSP.rootMeanSquare(mutable) * sqrt(Float(mutable.count))
        guard norm > 0 else { return nil }
        vDSP.divide(mutable, norm, result: &mutable)
        return mutable
    }
}
