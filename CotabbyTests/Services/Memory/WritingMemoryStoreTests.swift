import XCTest
@testable import Cotabby

@MainActor
final class WritingMemoryStoreTests: XCTestCase {
    func test_recordsAndPersistsAcrossInstances() {
        let suiteName = "cotabby.tests.writing-memory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WritingMemoryStore(defaults: defaults)
        store.recordAcceptance(
            acceptedText: "Deploy CotabbyInference tonight",
            bundleIdentifier: "com.apple.Terminal"
        )

        let snapshot = store.snapshot()
        XCTAssertTrue(snapshot.entries.contains { $0.text == "CotabbyInference" })

        let reloaded = WritingMemoryStore(defaults: defaults)
        XCTAssertTrue(reloaded.snapshot().entries.contains { $0.text == "CotabbyInference" })
    }

    func test_clearRemovesPersistedEntries() {
        let suiteName = "cotabby.tests.writing-memory-clear.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WritingMemoryStore(defaults: defaults)
        store.recordAcceptance(acceptedText: "Ship MatchaRelease", bundleIdentifier: nil)
        store.clear()
        XCTAssertTrue(store.snapshot().entries.isEmpty)
        XCTAssertTrue(WritingMemoryStore(defaults: defaults).snapshot().entries.isEmpty)
    }
}
