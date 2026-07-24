import XCTest
@testable import Cotabby

final class EngineStreamingPartialCoalescerTests: XCTestCase {
    func test_offer_deliversFirstPartialImmediately() {
        let coalescer = EngineStreamingPartialCoalescer(intervalNanoseconds: 50_000_000)
        var delivered: [String] = []
        let lock = NSLock()

        coalescer.offer("a") { snapshot in
            lock.lock()
            delivered.append(snapshot)
            lock.unlock()
        }

        lock.lock()
        let snapshots = delivered
        lock.unlock()

        XCTAssertEqual(
            snapshots,
            ["a"],
            "The first partial must not wait out the coalesce interval — that is TTFT for ghost text."
        )
    }

    func test_offer_coalescesBurstAfterFirstToLatestWins() async {
        let coalescer = EngineStreamingPartialCoalescer(intervalNanoseconds: 5_000_000)
        var delivered: [String] = []
        let lock = NSLock()

        coalescer.offer("a") { snapshot in
            lock.lock()
            delivered.append(snapshot)
            lock.unlock()
        }
        coalescer.offer("ab") { snapshot in
            lock.lock()
            delivered.append(snapshot)
            lock.unlock()
        }
        coalescer.offer("abc") { snapshot in
            lock.lock()
            delivered.append(snapshot)
            lock.unlock()
        }

        try? await Task.sleep(nanoseconds: 25_000_000)

        lock.lock()
        let snapshots = delivered
        lock.unlock()

        XCTAssertEqual(
            snapshots,
            ["a", "abc"],
            "First token paints immediately; the rest of a synchronous burst collapses to latest-wins."
        )
    }

    func test_offer_rearmsAfterDrain() async {
        let coalescer = EngineStreamingPartialCoalescer(intervalNanoseconds: 2_000_000)
        var delivered: [String] = []
        let lock = NSLock()

        coalescer.offer("first") { snapshot in
            lock.lock()
            delivered.append(snapshot)
            lock.unlock()
        }
        // First offer is synchronous; give the coalesce path a beat before the second offer.
        try? await Task.sleep(nanoseconds: 5_000_000)

        coalescer.offer("second") { snapshot in
            lock.lock()
            delivered.append(snapshot)
            lock.unlock()
        }
        try? await Task.sleep(nanoseconds: 15_000_000)

        lock.lock()
        let snapshots = delivered
        lock.unlock()

        XCTAssertEqual(snapshots, ["first", "second"])
    }
}
