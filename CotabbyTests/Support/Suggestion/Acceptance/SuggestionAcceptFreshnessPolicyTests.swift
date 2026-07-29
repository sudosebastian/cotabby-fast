import XCTest
@testable import Cotabby

final class SuggestionAcceptFreshnessPolicyTests: XCTestCase {
    func test_correctionAlwaysForcesRefresh() {
        XCTAssertTrue(
            SuggestionAcceptFreshnessPolicy.requiresForcedRefresh(
                isCorrection: true,
                millisecondsSinceLastCapture: 0
            )
        )
    }

    func test_continuationReusesVeryFreshSnapshot() {
        XCTAssertFalse(
            SuggestionAcceptFreshnessPolicy.requiresForcedRefresh(
                isCorrection: false,
                millisecondsSinceLastCapture: 5
            )
        )
    }

    func test_continuationForcesWhenOlderThanReuseWindow() {
        XCTAssertTrue(
            SuggestionAcceptFreshnessPolicy.requiresForcedRefresh(
                isCorrection: false,
                millisecondsSinceLastCapture: 11
            )
        )
    }

    func test_unknownAgeFailsClosed() {
        XCTAssertTrue(
            SuggestionAcceptFreshnessPolicy.requiresForcedRefresh(
                isCorrection: false,
                millisecondsSinceLastCapture: nil
            )
        )
    }
}
