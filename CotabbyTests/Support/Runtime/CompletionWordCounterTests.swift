import XCTest
@testable import Cotabby

final class CompletionWordCounterTests: XCTestCase {
    func test_apply_countsLetterRunsAsWords() {
        var counter = CompletionWordCounter()
        counter.apply("hello world")
        XCTAssertEqual(counter.wordCount, 2)
        counter.apply("-again")
        XCTAssertEqual(counter.wordCount, 3)
    }

    func test_wouldExceedLimit_allowsContinuationOfCurrentWord() {
        var counter = CompletionWordCounter()
        counter.apply("run")
        XCTAssertFalse(counter.wouldExceedLimit(applying: "ning", maximumWords: 1))
        XCTAssertTrue(counter.wouldExceedLimit(applying: " fast", maximumWords: 1))
    }

    func test_wordsStarted_doesNotMutate() {
        var counter = CompletionWordCounter()
        counter.apply("one ")
        XCTAssertEqual(counter.wordsStarted(by: "two three"), 2)
        XCTAssertEqual(counter.wordCount, 1)
    }
}
