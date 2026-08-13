import XCTest
@testable import Cotabby

final class TextSemanticEmbedderTests: XCTestCase {
    func test_cosineSimilarity_matchesAlignedUnitVectors() {
        let a: [Float] = [1, 0, 0, 0]
        let b: [Float] = [1, 0, 0, 0]
        let c: [Float] = [0, 1, 0, 0]
        XCTAssertEqual(TextSemanticEmbedder.cosineSimilarity(a, b), 1, accuracy: 0.0001)
        XCTAssertEqual(TextSemanticEmbedder.cosineSimilarity(a, c), 0, accuracy: 0.0001)
    }

    func test_queryTip_keepsTrailingWindow() {
        let prefix = String(repeating: "alpha ", count: 80) + "schedule the meeting"
        let tip = TextSemanticEmbedder.queryTip(from: prefix)
        XCTAssertLessThanOrEqual(tip.count, TextSemanticEmbedder.maximumQueryCharacters)
        XCTAssertTrue(tip.contains("schedule the meeting"))
        XCTAssertFalse(tip.hasPrefix(" "))
    }

    func test_embedQuery_rejectsShortPrefix() {
        XCTAssertNil(TextSemanticEmbedder.shared.embedQuery(from: "hi"))
    }

    func test_embedQuery_returnsVectorWhenModelAvailable() throws {
        let embedder = TextSemanticEmbedder.shared
        guard embedder.isAvailable else {
            throw XCTSkip("NLEmbedding.sentenceEmbedding unavailable on this host")
        }
        let vector = try XCTUnwrap(
            embedder.embedQuery(from: "Looking at the calendar schedule for tomorrow")
        )
        XCTAssertFalse(vector.isEmpty)
        // Unit vector: L2 norm ≈ 1.
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1, accuracy: 0.01)
    }

    func test_embeddingFilled_attachesVectors() throws {
        let embedder = TextSemanticEmbedder.shared
        guard embedder.isAvailable else {
            throw XCTSkip("NLEmbedding.sentenceEmbedding unavailable on this host")
        }
        let lines = [
            ScreenTextIndexLine(
                text: "Q3 planning calendar invite",
                displayID: 1,
                confidence: 0.8,
                capturedAt: Date(),
                windowHint: nil
            )
        ]
        let filled = embedder.embeddingFilled(lines: lines)
        XCTAssertNotNil(filled.first?.embedding)
        XCTAssertEqual(filled.first?.text, lines[0].text)
    }
}

final class ContextualRetrieverSemanticTests: XCTestCase {
    /// Related ambient line with no shared tokens should beat filler when embeddings align.
    func test_semanticBoostSurfacesRelatedAmbientLineWithoutTokenOverlap() throws {
        // Query ≈ [1, 0]; related ≈ [0.9, 0.1] after normalize-ish; filler ≈ [0, 1].
        let query: [Float] = [1, 0]
        let related: [Float] = [0.95, 0.3122] // ~unit, high cosine with query
        let filler: [Float] = [0, 1]

        let relatedNorm = hypot(related[0], related[1])
        let relatedUnit = [related[0] / relatedNorm, related[1] / relatedNorm]

        let ambient = [
            ScreenTextIndexLine(
                text: "Team standup notes from yesterday afternoon sync",
                displayID: 1,
                confidence: 0.9,
                capturedAt: Date(),
                windowHint: nil,
                embedding: filler
            ),
            ScreenTextIndexLine(
                text: "Calendar: design critique at 3pm in Orion",
                displayID: 1,
                confidence: 0.9,
                capturedAt: Date(),
                windowHint: nil,
                embedding: relatedUnit
            ),
        ]

        let result = ContextualRetriever.retrieve(
            // Prefix shares no tokens with either ambient line.
            prefixText: "Looking at the schedule",
            fieldOCR: nil,
            ambientLines: ambient,
            memory: .empty,
            recentFocus: [],
            currentBundleIdentifier: nil,
            queryEmbedding: query
        )

        let summary = try XCTUnwrap(result.screenSummary)
        // Both lines can fit the character budget; semantic ranking must put the related line first.
        XCTAssertTrue(
            summary.hasPrefix("Calendar"),
            "Expected calendar line to rank first, got: \(summary)"
        )
        if let calendarRange = summary.range(of: "Calendar"),
           let fillerRange = summary.range(of: "standup") {
            XCTAssertLessThan(
                calendarRange.lowerBound,
                fillerRange.lowerBound,
                "Semantic hit should precede the unrelated filler line"
            )
        }
    }

    func test_withoutQueryEmbedding_fallsBackToLexicalOnly() {
        let ambient = [
            ScreenTextIndexLine(
                text: "Unrelated filler about weather systems",
                displayID: 1,
                confidence: 0.9,
                capturedAt: Date(),
                windowHint: nil,
                embedding: [1, 0]
            ),
            ScreenTextIndexLine(
                text: "Looking at Ambient line that overlaps tokens",
                displayID: 1,
                confidence: 0.9,
                capturedAt: Date(),
                windowHint: nil,
                embedding: [0, 1]
            ),
        ]

        let result = ContextualRetriever.retrieve(
            prefixText: "Looking at Ambient",
            fieldOCR: nil,
            ambientLines: ambient,
            memory: .empty,
            recentFocus: [],
            currentBundleIdentifier: nil,
            queryEmbedding: nil
        )

        XCTAssertTrue(result.screenSummary?.contains("overlaps tokens") == true)
    }
}
