import Foundation

/// Pure rule for when acceptance must force a fresh AX capture before planning an insert or
/// replace. Stale snapshots after typeahead are the main source of "Tab ate a character" reports:
/// a correction planned against pre-typeahead text deletes the wrong UTF-16 count, and a
/// continuation reconcile against pre-accept text can consume Tab without inserting.
///
/// Kept outside the coordinator so the tradeoff (forced walk vs reuse) is unit-testable and so
/// latency-oriented `refreshIfStale` reuse cannot silently soften a destructive path again.
nonisolated enum SuggestionAcceptFreshnessPolicy {
    /// Corrections always force a refresh: they post backspaces sized from live preceding text.
    /// Continuations force a refresh when the snapshot is older than one short typeahead window
    /// (`maxReuseAgeMilliseconds`); fresher captures can be reused so rapid Tab does not stack
    /// identical AX walks.
    static func requiresForcedRefresh(
        isCorrection: Bool,
        millisecondsSinceLastCapture: Int?,
        maxReuseAgeMilliseconds: Int = 10
    ) -> Bool {
        if isCorrection {
            return true
        }
        guard let age = millisecondsSinceLastCapture else {
            // Unknown age (test fakes / cold start): fail closed and refresh.
            return true
        }
        return age > maxReuseAgeMilliseconds
    }
}
