import XCTest
@testable import Cotabby

final class WritingMemoryLearnerTests: XCTestCase {
    func test_extractsRareTermsAndNgramsFromAcceptance() {
        let candidates = WritingMemoryLearner.candidates(
            from: "Ship CotabbyInference to main before Friday",
            bundleIdentifier: "com.apple.Safari",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let rareTerms = candidates.filter { $0.kind == .rareTerm }.map(\.text)
        let ngrams = candidates.filter { $0.kind == .ngram }.map(\.text)

        XCTAssertTrue(rareTerms.contains("CotabbyInference"))
        XCTAssertFalse(rareTerms.contains { $0.lowercased() == "to" })
        XCTAssertTrue(ngrams.contains { $0.localizedCaseInsensitiveContains("CotabbyInference") })
        XCTAssertEqual(candidates.first?.bundleIdentifier, "com.apple.Safari")
    }

    func test_skipsStopWordsAsRareTerms() {
        let candidates = WritingMemoryLearner.candidates(
            from: "the and or but if then else",
            bundleIdentifier: nil
        )
        XCTAssertTrue(candidates.filter { $0.kind == .rareTerm }.isEmpty)
    }
}

final class ContextualRetrieverTests: XCTestCase {
    func test_prefersFieldOCRAndBoundsScreenSummary() {
        let ambient = (0..<40).map { index in
            ScreenTextIndexLine(
                text: "Ambient line number \(index) with filler text for ranking",
                displayID: 1,
                confidence: 0.9,
                capturedAt: Date(),
                windowHint: nil
            )
        }
        let result = ContextualRetriever.retrieve(
            prefixText: "Looking at Ambient",
            fieldOCR: "Calendar: Q3 planning 3pm",
            ambientLines: ambient,
            memory: .empty,
            recentFocus: [],
            currentBundleIdentifier: nil
        )

        XCTAssertNotNil(result.screenSummary)
        XCTAssertTrue(result.screenSummary?.contains("Calendar") == true)
        XCTAssertLessThanOrEqual(result.screenSummary?.count ?? 0, ContextualRetriever.maxScreenCharacters)
    }

    func test_glossaryReturnsRareTermsOverlappingPrefix() {
        let memory = WritingMemorySnapshot(entries: [
            WritingMemoryEntry(
                text: "CotabbyInference",
                kind: .rareTerm,
                frequency: 4,
                lastUsedAt: Date(),
                bundleIdentifier: "com.apple.dt.Xcode"
            ),
            WritingMemoryEntry(
                text: "UnrelatedTerm",
                kind: .rareTerm,
                frequency: 1,
                lastUsedAt: Date().addingTimeInterval(-86_400 * 40),
                bundleIdentifier: nil
            )
        ])

        let result = ContextualRetriever.retrieve(
            prefixText: "Wire Cotabby",
            fieldOCR: nil,
            ambientLines: [],
            memory: memory,
            recentFocus: [],
            currentBundleIdentifier: "com.apple.dt.Xcode"
        )

        XCTAssertEqual(result.memoryGlossary, "CotabbyInference")
    }

    func test_instantContinuationFromFrequentNgram() {
        let memory = WritingMemorySnapshot(entries: [
            WritingMemoryEntry(
                text: "pull request review",
                kind: .ngram,
                frequency: 3,
                lastUsedAt: Date(),
                bundleIdentifier: nil
            )
        ])

        let remainder = ContextualRetriever.instantContinuation(
            prefixText: "Please finish the pull request",
            memory: memory
        )
        XCTAssertEqual(remainder, " review")
    }
}
