import Foundation

/// Pure "has the host published this keystroke?" predicate used by the host-publish poll and the
/// late-publish arm. Lives in Support so the coordinator cannot drift the two call sites apart,
/// and so composition / replace-in-place hosts that keep the caret location still can be detected
/// via length or selection-length changes.
nonisolated enum HostPublishChangeDetector {
    /// Baseline captured at keystroke time. Fields are optional because focus may already be gone.
    struct Baseline: Equatable, Sendable {
        let precedingText: String?
        let elementIdentifier: String?
        let selectionLocation: Int?
        let selectionLength: Int?
    }

    /// Live AX fields to compare against the baseline.
    struct Snapshot: Equatable, Sendable {
        let precedingText: String?
        let elementIdentifier: String?
        let selectionLocation: Int?
        let selectionLength: Int?
    }

    /// True when any signal that reliably means "the host processed input" has moved.
    static func hasPublished(from baseline: Baseline, to snapshot: Snapshot) -> Bool {
        if snapshot.precedingText != baseline.precedingText {
            return true
        }
        if snapshot.elementIdentifier != baseline.elementIdentifier {
            return true
        }
        if snapshot.selectionLocation != baseline.selectionLocation {
            return true
        }
        // Composition and some replace-in-place editors keep the caret location while growing a
        // marked range; treating length as a publish signal closes that gap.
        if snapshot.selectionLength != baseline.selectionLength {
            return true
        }
        // UTF-16 length can move even when String equality is preserved across normalization
        // edge cases; comparing counts is also a cheap sentinel for truncated AX values flipping
        // back to full text after a composition commit.
        let baselineCount = baseline.precedingText?.utf16.count
        let snapshotCount = snapshot.precedingText?.utf16.count
        if baselineCount != snapshotCount {
            return true
        }
        return false
    }
}
