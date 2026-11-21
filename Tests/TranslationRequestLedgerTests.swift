import XCTest
@testable import OrionSubtitles

final class TranslationRequestLedgerTests: XCTestCase {
    func testRequestIsClaimedOnceAndCompletedOnce() {
        var ledger = TranslationRequestLedger()
        let id = UUID()

        ledger.enqueue(id)
        XCTAssertTrue(ledger.claim(id))
        XCTAssertFalse(ledger.claim(id))
        XCTAssertTrue(ledger.complete(id))
        XCTAssertFalse(ledger.complete(id))
        XCTAssertTrue(ledger.completed.contains(id))
    }

    func testCancelledRequestCanBeRequeuedWithoutCompleting() {
        var ledger = TranslationRequestLedger()
        let id = UUID()

        ledger.enqueue(id)
        XCTAssertTrue(ledger.claim(id))
        ledger.requeue(id)
        XCTAssertTrue(ledger.pending.contains(id))
        XCTAssertTrue(ledger.claim(id))
        XCTAssertTrue(ledger.complete(id))
    }

    func testCompletedRequestCannotBeEnqueuedAgain() {
        var ledger = TranslationRequestLedger()
        let id = UUID()

        ledger.enqueue(id)
        XCTAssertTrue(ledger.claim(id))
        XCTAssertTrue(ledger.complete(id))
        ledger.enqueue(id)

        XCTAssertFalse(ledger.pending.contains(id))
        XCTAssertFalse(ledger.claim(id))
    }
}
