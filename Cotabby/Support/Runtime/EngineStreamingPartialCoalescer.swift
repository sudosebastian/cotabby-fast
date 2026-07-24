import Foundation

/// Latest-wins coalescer for engine streaming partials.
///
/// Decode threads (llama) and SSE loops (OpenAI-compatible) can emit one partial per token. Hopping
/// to the MainActor and running `SuggestionTextNormalizer` on every emission is far more expensive
/// than the coordinator's already-coalesced overlay apply. This type collapses a burst into one
/// delivery every `intervalNanoseconds`, so enabling streaming by default stays latency-positive.
///
/// Ownership: engines create one coalescer per streaming generation. It is not shared across
/// requests, so a cancelled decode simply stops offering — no explicit flush is required for the
/// authoritative final result (which still travels the non-streaming return path).
final class EngineStreamingPartialCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingRaw: String?
    private var isDrainScheduled = false
    private let intervalNanoseconds: UInt64

    /// ~16ms matches one display refresh and is short enough that ghost text still feels live.
    init(intervalNanoseconds: UInt64 = 16_000_000) {
        self.intervalNanoseconds = intervalNanoseconds
    }

    /// Offers a new cumulative raw completion. `deliver` runs off the decode thread after the
    /// coalesce window with the latest raw string; the caller is responsible for MainActor hops
    /// and normalization inside `deliver`.
    func offer(_ raw: String, deliver: @escaping @Sendable (String) -> Void) {
        lock.lock()
        pendingRaw = raw
        if isDrainScheduled {
            lock.unlock()
            return
        }
        isDrainScheduled = true
        lock.unlock()

        Task {
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
            // Drain until empty so a partial that arrives during `deliver` is not dropped while
            // `isDrainScheduled` is still true (which would skip scheduling a new Task).
            while true {
                let snapshot: String?
                lock.lock()
                snapshot = pendingRaw
                pendingRaw = nil
                if snapshot == nil {
                    isDrainScheduled = false
                    lock.unlock()
                    return
                }
                lock.unlock()
                deliver(snapshot!)
            }
        }
    }
}
