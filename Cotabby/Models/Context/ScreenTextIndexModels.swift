import CoreGraphics
import Foundation

/// File overview:
/// Values for the ambient multi-display screen text index. The indexer captures and OCRs displays
/// in the background; these models are the searchable result the critical suggestion path reads
/// without waiting on Vision.

/// One OCR line from an ambient display capture, with enough metadata for ranking.
struct ScreenTextIndexLine: Equatable, Sendable {
    let text: String
    let displayID: CGDirectDisplayID
    let confidence: Float
    let capturedAt: Date
    /// Best-effort owning app name when ScreenCaptureKit exposed a window title near the line.
    let windowHint: String?
}

/// Immutable snapshot of the current ambient index.
struct ScreenTextIndexSnapshot: Equatable, Sendable {
    let lines: [ScreenTextIndexLine]
    let updatedAt: Date?

    static let empty = ScreenTextIndexSnapshot(lines: [], updatedAt: nil)
}
