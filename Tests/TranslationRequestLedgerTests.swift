import XCTest
@testable import OrionSubtitles

final class TranslationRequestLedgerTests: XCTestCase {
	func testRemotePlayLifecycleGateAllowsOnlyOneStart() {
		var gate = RemotePlayLifecycleGate()
		let id = try! XCTUnwrap(gate.begin())
		XCTAssertNil(gate.begin())
		gate.markActive(id)
		XCTAssertNil(gate.begin())
	}

	func testRemotePlayLifecycleGateAllowsOneStopAndCleanRestart() {
		var gate = RemotePlayLifecycleGate()
		let id = try! XCTUnwrap(gate.begin())
		gate.markActive(id)
		XCTAssertEqual(gate.beginStop(), id)
		XCTAssertNil(gate.beginStop())
		gate.finishStop(id)
		XCTAssertNotNil(gate.begin())
	}

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

	func testVideoAccessUnitSplitsThreeAndFourByteAnnexBStartCodes() {
		let bytes: [UInt8] = [
			0, 0, 0, 1, 0x67, 0x64, 0,
			0, 0, 1, 0x68, 0xee,
			0, 0, 0, 1, 0x65, 0x88, 0x84,
		]
		let ranges = bytes.withUnsafeBufferPointer { buffer in
			VideoDecoder.splitAnnexB(buffer.baseAddress!, count: buffer.count)
		}
		XCTAssertEqual(ranges.map { Array(bytes[$0]) }, [
			[0x67, 0x64, 0],
			[0x68, 0xee],
			[0x65, 0x88, 0x84],
		])
	}

	func testVideoAccessUnitWithNoStartCodeProducesNoFrames() {
		let bytes: [UInt8] = [0x67, 0x64, 0, 0x65]
		let ranges = bytes.withUnsafeBufferPointer { buffer in
			VideoDecoder.splitAnnexB(buffer.baseAddress!, count: buffer.count)
		}
		XCTAssertTrue(ranges.isEmpty)
	}
}
