import Foundation

/// Narrow persistence surface for `WritingMemoryStore`, matching `EmojiUsageStore`'s test seam.
protocol WritingMemoryDefaults: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: WritingMemoryDefaults {}

/// File overview:
/// Persists rare terms and accepted n-grams learned from Tab accepts. Main-actor owned so the
/// suggestion coordinator can record and retrieve between keystrokes without actor hops. The
/// critical path only reads a cheap `snapshot()`; learning runs after acceptance bookkeeping.
///
/// Why a dedicated store (not Extended Context): user notes are intentional and stable; this memory
/// grows from usage and must stay bounded, decayed, and retrieve-only so it cannot blow the prompt
/// budget the way dumping a frequency dictionary would.
@MainActor
final class WritingMemoryStore {
    private let defaults: WritingMemoryDefaults
    private var entriesByKey: [String: WritingMemoryEntry]

    private static let storageKey = "cotabbyWritingMemory"
    private static let maxEntries = 400
    private static let trimTarget = 300

    private struct Persisted: Codable {
        var entries: [WritingMemoryEntry]
    }

    init(defaults: WritingMemoryDefaults = UserDefaults.standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            var map: [String: WritingMemoryEntry] = [:]
            for entry in decoded.entries {
                map[entry.normalizedKey] = entry
            }
            entriesByKey = map
        } else {
            entriesByKey = [:]
        }
    }

    nonisolated deinit {}

    /// Merges learner candidates from one accepted chunk into the store.
    func recordAcceptance(
        acceptedText: String,
        bundleIdentifier: String?,
        now: Date = Date()
    ) {
        let candidates = WritingMemoryLearner.candidates(
            from: acceptedText,
            bundleIdentifier: bundleIdentifier,
            now: now
        )
        guard !candidates.isEmpty else { return }

        for candidate in candidates {
            let key = candidate.normalizedKey
            if var existing = entriesByKey[key] {
                existing.frequency += 1
                existing.lastUsedAt = now
                // Prefer the most recent bundle affinity when the same term appears in multiple apps.
                if let bundle = candidate.bundleIdentifier {
                    existing.bundleIdentifier = bundle
                }
                entriesByKey[key] = existing
            } else {
                entriesByKey[key] = candidate
            }
        }

        trimIfNeeded()
        persist()
    }

    func snapshot() -> WritingMemorySnapshot {
        WritingMemorySnapshot(entries: Array(entriesByKey.values))
    }

    func clear() {
        entriesByKey = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func trimIfNeeded() {
        guard entriesByKey.count > Self.maxEntries else { return }
        let sorted = entriesByKey.values.sorted { lhs, rhs in
            // Keep higher frequency and more recent entries.
            if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }
        let kept = sorted.prefix(Self.trimTarget)
        entriesByKey = Dictionary(uniqueKeysWithValues: kept.map { ($0.normalizedKey, $0) })
    }

    private func persist() {
        let payload = Persisted(entries: Array(entriesByKey.values))
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
