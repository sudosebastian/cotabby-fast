import Foundation

/// Pure decision helper for llama autocomplete KV reuse.
///
/// Hybrid/SWA catalog models reject mid-sequence `trimKV`, so the historical path skipped *all*
/// reuse once that was learned — including the case where the new prompt is a strict extension of
/// the tokens already resident in KV. Extending does not need trim: `decodePrompt` can append the
/// delta at `start_position = stored.count`. Keeping this policy pure makes the branch unit-testable
/// without loading a GGUF.
///
/// Ownership: `LlamaRuntimeCore.obtainAutocompleteSequence` is the only production caller.
enum LlamaKVReusePolicy {
    /// How the next request should attach to an existing autocomplete sequence.
    enum Decision: Equatable, Sendable {
        /// Destroy any live sequence and build from scratch.
        case fresh
        /// Keep the live sequence and decode only `newTokens[reusable...]` (no trim).
        case extend(reusableTokenCount: Int)
        /// Trim KV down to `reusableTokenCount`, then decode the remainder (classic reuse).
        case trimReuse(reusableTokenCount: Int)
    }

    /// Chooses reuse strategy for one obtain-sequence call.
    static func decide(
        modelRejectsPartialTrims: Bool,
        hasLiveSequence: Bool,
        storedTokens: [Int32],
        newTokens: [Int32],
        fingerprintMatches: Bool
    ) -> Decision {
        guard hasLiveSequence, fingerprintMatches, !storedTokens.isEmpty, !newTokens.isEmpty else {
            return .fresh
        }

        let common = commonPrefixCount(storedTokens, newTokens)

        if modelRejectsPartialTrims {
            // Strict extension (or exact match): stored tokens are a prefix of the new prompt.
            // Exact match leaves remaining empty and reuses the already-seeded sequence (prefill →
            // generate). Divergent or shorter prompts cannot drop suffix tokens without trim.
            guard common == storedTokens.count, newTokens.count >= storedTokens.count else {
                return .fresh
            }
            return .extend(reusableTokenCount: storedTokens.count)
        }

        // Classic path: reserve at least one token to re-decode so the sampler is re-seeded.
        guard newTokens.count > 1 else { return .fresh }
        let reusable = min(common, newTokens.count - 1)
        guard reusable > 0 else { return .fresh }
        return .trimReuse(reusableTokenCount: reusable)
    }

    static func commonPrefixCount<Element: Equatable>(_ lhs: [Element], _ rhs: [Element]) -> Int {
        var index = 0
        let limit = min(lhs.count, rhs.count)
        while index < limit, lhs[index] == rhs[index] {
            index += 1
        }
        return index
    }
}

/// How prompt KV was obtained for one generation — logged and shown in Performance tracking.
enum LlamaKVReuseMode: String, Equatable, Sendable, Codable {
    case fresh
    case trim
    case extend
}

/// Wall-clock breakdown for one llama generate. Optional fields stay nil when a stage did not run
/// (for example, no streamed partial → no TTFT).
struct LlamaGenerationTiming: Equatable, Sendable {
    let prefillMs: Int
    let decodeMs: Int
    let timeToFirstPartialMs: Int?
    let reuseMode: LlamaKVReuseMode
    let promptTokenCount: Int
    let generatedTokenCount: Int
}
