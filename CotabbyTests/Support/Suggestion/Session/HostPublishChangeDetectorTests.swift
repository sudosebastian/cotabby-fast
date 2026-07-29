import XCTest
@testable import Cotabby

final class HostPublishChangeDetectorTests: XCTestCase {
    private let baseline = HostPublishChangeDetector.Baseline(
        precedingText: "hello",
        elementIdentifier: "field",
        selectionLocation: 5,
        selectionLength: 0
    )

    func test_unchangedSnapshotIsNotAPublish() {
        XCTAssertFalse(
            HostPublishChangeDetector.hasPublished(
                from: baseline,
                to: HostPublishChangeDetector.Snapshot(
                    precedingText: "hello",
                    elementIdentifier: "field",
                    selectionLocation: 5,
                    selectionLength: 0
                )
            )
        )
    }

    func test_precedingTextChangeIsAPublish() {
        XCTAssertTrue(
            HostPublishChangeDetector.hasPublished(
                from: baseline,
                to: HostPublishChangeDetector.Snapshot(
                    precedingText: "hello ",
                    elementIdentifier: "field",
                    selectionLocation: 6,
                    selectionLength: 0
                )
            )
        )
    }

    func test_selectionLengthChangeAloneIsAPublish() {
        // Composition / marked-text hosts keep the caret location while growing the selection.
        XCTAssertTrue(
            HostPublishChangeDetector.hasPublished(
                from: baseline,
                to: HostPublishChangeDetector.Snapshot(
                    precedingText: "hello",
                    elementIdentifier: "field",
                    selectionLocation: 5,
                    selectionLength: 1
                )
            )
        )
    }

    func test_elementIdentityChangeIsAPublish() {
        XCTAssertTrue(
            HostPublishChangeDetector.hasPublished(
                from: baseline,
                to: HostPublishChangeDetector.Snapshot(
                    precedingText: "hello",
                    elementIdentifier: "other-field",
                    selectionLocation: 5,
                    selectionLength: 0
                )
            )
        )
    }
}
