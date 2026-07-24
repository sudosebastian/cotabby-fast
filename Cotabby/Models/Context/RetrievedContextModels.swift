import Foundation

/// File overview:
/// Values produced by `ContextualRetriever` for prompt injection. Retrieval keeps the LLM preface
/// small: the ambient screen index and writing memory can be large, but only the top-scoring
/// snippets reach the model. That protects llama KV reuse and the shared prompt token budget.
///
/// These are plain Sendable values so request construction stays pure once retrieval has finished
/// on the main actor.

/// One ranked text snippet considered for the autocomplete preface.
struct RetrievedContextSnippet: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case fieldOCR
        case ambientScreen
        case writingMemory
        case recentFocus
    }

    let text: String
    let source: Source
    let score: Double
}

/// Bounded prompt-ready context assembled from field OCR, ambient screen text, writing memory,
/// and recent focus. Empty strings mean "omit the section" for renderers.
struct RetrievedPromptContext: Equatable, Sendable {
    /// Ranked screen / nearby text for the llama "Nearby on screen" / FM "Screen content" section.
    let screenSummary: String?
    /// Rare terms and short phrases learned from accepts, for a small glossary section.
    let memoryGlossary: String?
    /// Instant continuation from acceptance memory when confidence is high enough to skip the LLM.
    let instantContinuation: String?

    static let empty = RetrievedPromptContext(
        screenSummary: nil,
        memoryGlossary: nil,
        instantContinuation: nil
    )
}
