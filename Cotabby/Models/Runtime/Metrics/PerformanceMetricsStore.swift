import Combine
import Foundation
import Logging

/// File overview:
/// In-memory + UserDefaults-backed ring buffer of the most recent LLM generation latencies.
/// Capped at `maximumEntries` so the persisted blob stays small and the Performance settings pane
/// renders a bounded list without virtualization. Records flow in from `SuggestionEngineRouter`
/// only when the user has enabled performance tracking in Settings, so the default user pays no
/// storage or write cost.

/// One recorded LLM request — kept intentionally narrow: just the three fields the
/// Performance pane shows. Codable so the whole array round-trips through UserDefaults
/// as a JSON blob.
struct PerformanceMetricEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let timestamp: Date
    let modelName: String
    let latencyMs: Int

    init(id: UUID = UUID(), timestamp: Date = Date(), modelName: String, latencyMs: Int) {
        self.id = id
        self.timestamp = timestamp
        self.modelName = modelName
        self.latencyMs = latencyMs
    }
}

@MainActor
final class PerformanceMetricsStore: ObservableObject {
    /// Hard cap on retained entries. The UI assumes the entire list is renderable without
    /// virtualization, so growing this past a few hundred would require revisiting the pane.
    static let maximumEntries = 100

    /// How long to coalesce UserDefaults writes during rapid typing. In-memory `@Published`
    /// entries update immediately for the Performance pane; disk sync waits so encode+write
    /// never sits on the suggestion completion path for every keystroke.
    static let persistenceDebounceSeconds: TimeInterval = 2.0

    @Published private(set) var entries: [PerformanceMetricEntry]

    private let userDefaults: UserDefaults
    private static let entriesDefaultsKey = "cotabbyPerformanceMetricEntries"
    private var pendingPersistWorkItem: DispatchWorkItem?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        entries = Self.loadEntries(from: userDefaults)
    }

    /// Append a new metric and drop the oldest entries above the cap. Updates memory immediately;
    /// persistence is debounced so a burst of tracked generations does not encode JSON on every
    /// completion.
    func record(modelName: String, latencyMs: Int, timestamp: Date = Date()) {
        let entry = PerformanceMetricEntry(
            timestamp: timestamp,
            modelName: modelName,
            latencyMs: latencyMs
        )
        var updated = entries
        updated.append(entry)
        if updated.count > Self.maximumEntries {
            updated.removeFirst(updated.count - Self.maximumEntries)
        }
        entries = updated
        schedulePersist(updated)
    }

    func clear() {
        pendingPersistWorkItem?.cancel()
        pendingPersistWorkItem = nil
        guard !entries.isEmpty else { return }
        entries = []
        userDefaults.removeObject(forKey: Self.entriesDefaultsKey)
    }

    /// Flushes any pending disk write immediately. Call from app termination / backgrounding so
    /// the last few tracked requests are not lost to debounce cancellation.
    func flushPendingPersistence() {
        pendingPersistWorkItem?.cancel()
        pendingPersistWorkItem = nil
        persist(entries)
    }

    private func schedulePersist(_ entries: [PerformanceMetricEntry]) {
        pendingPersistWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persist(entries)
        }
        pendingPersistWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.persistenceDebounceSeconds,
            execute: work
        )
    }

    private func persist(_ entries: [PerformanceMetricEntry]) {
        // Encoding `[PerformanceMetricEntry]` (UUID/Date/String/Int) shouldn't fail in practice, but
        // a silent return here would make "metrics vanish between sessions" undiagnosable. Log the
        // underlying error so the cause shows up in the standard JSONL stream when it does happen.
        do {
            let data = try JSONEncoder().encode(entries)
            userDefaults.set(data, forKey: Self.entriesDefaultsKey)
        } catch {
            CotabbyLogger.app.error(
                "Failed to persist performance metrics: \(error.localizedDescription)",
                metadata: ["entry_count": .stringConvertible(entries.count)]
            )
        }
    }

    private static func loadEntries(from userDefaults: UserDefaults) -> [PerformanceMetricEntry] {
        guard let data = userDefaults.data(forKey: Self.entriesDefaultsKey),
              let decoded = try? JSONDecoder().decode([PerformanceMetricEntry].self, from: data)
        else {
            return []
        }
        if decoded.count > maximumEntries {
            return Array(decoded.suffix(maximumEntries))
        }
        return decoded
    }
}
