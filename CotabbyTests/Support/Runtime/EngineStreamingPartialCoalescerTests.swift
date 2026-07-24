import XCTest
@testable import Cotabby

final class EngineStreamingPartialCoalescerTests: XCTestCase {
    func test_offer_coalescesBurstToLatestWins() async {
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

        XCTAssertEqual(snapshots, ["abc"], "A synchronous burst must collapse to the latest cumulative.")
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
        try? await Task.sleep(nanoseconds: 15_000_000)

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
