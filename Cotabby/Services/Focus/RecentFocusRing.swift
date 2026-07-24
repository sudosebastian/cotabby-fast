import Foundation

/// File overview:
/// Bounded ring of recently focused writing surfaces. Updated from focus snapshots; consumed only as
/// a retrieval prior. Keeping this as its own type (instead of expanding `FocusTrackingModel`’s
/// published surface) avoids SwiftUI churn on every focus poll — the ring is read on demand at
/// request-build time.
@MainActor
final class RecentFocusRing {
    private var entries: [RecentFocusEntry] = []
    private let capacity: Int
    private var lastIdentityKey: String?

    init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    /// Records a focus surface when its identity changes. Ignores empty / Cotabby-self polls when
    /// `ignoredBundleIdentifier` matches.
    func record(
        applicationName: String?,
        bundleIdentifier: String?,
        windowTitle: String?,
        focusedURLString: String?,
        ignoredBundleIdentifier: String?,
        now: Date = Date()
    ) {
        guard let applicationName, !applicationName.isEmpty else { return }
        if let ignored = ignoredBundleIdentifier,
           bundleIdentifier == ignored {
            return
        }

        let entry = RecentFocusEntry(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            windowTitle: windowTitle,
            focusedURLString: focusedURLString,
            recordedAt: now
        )
        guard entry.identityKey != lastIdentityKey else { return }
        lastIdentityKey = entry.identityKey

        entries.removeAll { $0.identityKey == entry.identityKey }
        entries.insert(entry, at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    func snapshot() -> [RecentFocusEntry] {
        entries
    }

    func clear() {
        entries = []
        lastIdentityKey = nil
    }
}
