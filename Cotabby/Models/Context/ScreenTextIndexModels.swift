import CoreGraphics
import Foundation

/// File overview:
/// Values for the ambient multi-display screen text index. The indexer captures and OCRs displays
/// in the background; these models are the searchable result the critical suggestion path reads
/// without waiting on Vision.
///
/// Optional `embedding` is a unit sentence vector filled after OCR by `TextSemanticEmbedder`. The
/// suggestion path only reads whatever is already warm — it never waits on embedding work.

/// One OCR line from an ambient display capture, with enough metadata for ranking.
struct ScreenTextIndexLine: Equatable, Sendable {
    let text: String
    let displayID: CGDirectDisplayID
    let confidence: Float
    let capturedAt: Date
    /// Best-effort owning app name when ScreenCaptureKit exposed a window title near the line.
    let windowHint: String?
    /// Unit-length sentence embedding for semantic ranking, or `nil` when unavailable / not yet filled.
    let embedding: [Float]?

    init(
        text: String,
        displayID: CGDirectDisplayID,
        confidence: Float,
        capturedAt: Date,
        windowHint: String?,
        embedding: [Float]? = nil
    ) {
        self.text = text
        self.displayID = displayID
        self.confidence = confidence
        self.capturedAt = capturedAt
        self.windowHint = windowHint
        self.embedding = embedding
    }
}

/// Immutable snapshot of the current ambient index.
struct ScreenTextIndexSnapshot: Equatable, Sendable {
    let lines: [ScreenTextIndexLine]
    let updatedAt: Date?

    static let empty = ScreenTextIndexSnapshot(lines: [], updatedAt: nil)
}
