import XCTest

@testable import escctrl

/// Exercises the tap-vs-hold decision logic with a fake clock so timing is deterministic.
final class CapsLockTrackerTests: XCTestCase {
    private var clockNs: UInt64 = 0

    private func makeTracker(thresholdMs: UInt64 = 200) -> CapsLockTracker {
        clockNs = 0
        return CapsLockTracker(tapThresholdMs: thresholdMs, now: { [unowned self] in self.clockNs })
    }

    private func advance(ms: UInt64) {
        clockNs &+= ms * 1_000_000
    }

    func testQuickTapFiresEscape() {
        let t = makeTracker()
        t.press()
        advance(ms: 50)
        XCTAssertTrue(t.release(), "a fast press with no other key should be a tap")
    }

    func testSlowHoldDoesNotFire() {
        let t = makeTracker()
        t.press()
        advance(ms: 250)
        XCTAssertFalse(t.release(), "a press past the threshold is a hold, not a tap")
    }

    func testThresholdIsExclusive() {
        let t = makeTracker(thresholdMs: 200)
        t.press()
        advance(ms: 200)  // exactly the threshold counts as a hold (elapsed < threshold is false)
        XCTAssertFalse(t.release())
    }

    func testInterruptedPressNeverTaps() {
        let t = makeTracker()
        t.press()
        advance(ms: 10)
        t.interrupt()  // another key came down → unambiguously a hold
        XCTAssertFalse(t.release())
    }

    func testHeldStateTransitions() {
        let t = makeTracker()
        XCTAssertFalse(t.isHeld)
        t.press()
        XCTAssertTrue(t.isHeld)
        t.interrupt()
        XCTAssertTrue(t.isHeld, "still held after the modifier latches")
        _ = t.release()
        XCTAssertFalse(t.isHeld)
    }

    func testReleaseResetsForNextCycle() {
        let t = makeTracker()
        t.press()
        advance(ms: 10)
        t.interrupt()
        XCTAssertFalse(t.release())

        // A fresh, clean tap right after an interrupted hold must still fire.
        t.press()
        advance(ms: 10)
        XCTAssertTrue(t.release())
    }

    func testReleaseWithoutPressIsNotATap() {
        let t = makeTracker()
        XCTAssertFalse(t.release(), "releasing from idle should never fire Escape")
    }
}
