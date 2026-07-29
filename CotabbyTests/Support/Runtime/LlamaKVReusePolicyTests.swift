import XCTest
@testable import Cotabby

final class LlamaKVReusePolicyTests: XCTestCase {
    func test_freshWhenNoLiveSequence() {
        let decision = LlamaKVReusePolicy.decide(
            modelRejectsPartialTrims: true,
            hasLiveSequence: false,
            storedTokens: [1, 2, 3],
            newTokens: [1, 2, 3, 4],
            fingerprintMatches: true
        )
        XCTAssertEqual(decision, .fresh)
    }

    func test_extendWhenSWAAndNewPromptStrictlyExtendsStored() {
        let decision = LlamaKVReusePolicy.decide(
            modelRejectsPartialTrims: true,
            hasLiveSequence: true,
            storedTokens: [10, 20, 30],
            newTokens: [10, 20, 30, 40, 50],
            fingerprintMatches: true
        )
        XCTAssertEqual(decision, .extend(reusableTokenCount: 3))
    }

    func test_extendExactMatchForPrefillThenGenerate() {
        let decision = LlamaKVReusePolicy.decide(
            modelRejectsPartialTrims: true,
            hasLiveSequence: true,
            storedTokens: [10, 20, 30],
            newTokens: [10, 20, 30],
            fingerprintMatches: true
        )
        XCTAssertEqual(decision, .extend(reusableTokenCount: 3))
    }

    func test_freshWhenSWAAndPromptDiverges() {
        let decision = LlamaKVReusePolicy.decide(
            modelRejectsPartialTrims: true,
            hasLiveSequence: true,
            storedTokens: [10, 20, 30],
            newTokens: [10, 20, 99],
            fingerprintMatches: true
        )
        XCTAssertEqual(decision, .fresh)
    }

    func test_freshWhenSWAAndPromptShrinks() {
        let decision = LlamaKVReusePolicy.decide(
            modelRejectsPartialTrims: true,
            hasLiveSequence: true,
            storedTokens: [10, 20, 30],
            newTokens: [10, 20],
            fingerprintMatches: true
        )
        XCTAssertEqual(decision, .fresh)
    }

    func test_trimReuseReservesLastTokenForReseed() {
        let decision = LlamaKVReusePolicy.decide(
            modelRejectsPartialTrims: false,
            hasLiveSequence: true,
            storedTokens: [1, 2, 3, 4],
            newTokens: [1, 2, 3, 4, 5],
            fingerprintMatches: true
        )
        // common=4, newCount-1=4 → reusable 4
        XCTAssertEqual(decision, .trimReuse(reusableTokenCount: 4))
    }

    func test_trimReuseOnExactMatchReservesOneToken() {
        let decision = LlamaKVReusePolicy.decide(
            modelRejectsPartialTrims: false,
            hasLiveSequence: true,
            storedTokens: [1, 2, 3],
            newTokens: [1, 2, 3],
            fingerprintMatches: true
        )
        XCTAssertEqual(decision, .trimReuse(reusableTokenCount: 2))
    }

    func test_freshWhenFingerprintMismatch() {
        let decision = LlamaKVReusePolicy.decide(
            modelRejectsPartialTrims: true,
            hasLiveSequence: true,
            storedTokens: [1, 2],
            newTokens: [1, 2, 3],
            fingerprintMatches: false
        )
        XCTAssertEqual(decision, .fresh)
    }

    func test_freshWhenAllowReuseDisabledEvenIfExtendWouldApply() {
        // User toggle Off (Fresh): force rebuild even when the prompt is a strict SWA extension.
        let decision = LlamaKVReusePolicy.decide(
            modelRejectsPartialTrims: true,
            hasLiveSequence: true,
            storedTokens: [10, 20, 30],
            newTokens: [10, 20, 30, 40, 50],
            fingerprintMatches: true,
            allowReuse: false
        )
        XCTAssertEqual(decision, .fresh)
    }

    func test_freshWhenAllowReuseDisabledEvenIfTrimReuseWouldApply() {
        let decision = LlamaKVReusePolicy.decide(
            modelRejectsPartialTrims: false,
            hasLiveSequence: true,
            storedTokens: [1, 2, 3, 4],
            newTokens: [1, 2, 3, 4, 5],
            fingerprintMatches: true,
            allowReuse: false
        )
        XCTAssertEqual(decision, .fresh)
    }
}
