import XCTest
import CoreGraphics
@testable import NiceTouchCore

final class FnActivationGateTests: XCTestCase {
    func testFnIsRequiredByDefault() {
        var gate = FnActivationGate()
        XCTAssertFalse(gate.allowsFrame(contactCount: 3, fnPressed: false))
        XCTAssertFalse(gate.allowsFrame(contactCount: 0, fnPressed: false))
    }
    func testHeldFnAllowsTheWholeGestureIncludingLift() {
        var gate = FnActivationGate()
        XCTAssertTrue(gate.allowsFrame(contactCount: 1, fnPressed: true))
        XCTAssertTrue(gate.allowsFrame(contactCount: 3, fnPressed: true))
        XCTAssertTrue(gate.allowsFrame(contactCount: 0, fnPressed: true))
        XCTAssertFalse(gate.allowsFrame(contactCount: 0, fnPressed: true))
    }
    func testPressingFnHalfwayDoesNotActivate() {
        var gate = FnActivationGate()
        XCTAssertFalse(gate.allowsFrame(contactCount: 1, fnPressed: false))
        XCTAssertFalse(gate.allowsFrame(contactCount: 3, fnPressed: true))
        XCTAssertFalse(gate.allowsFrame(contactCount: 0, fnPressed: true))
        XCTAssertTrue(gate.allowsFrame(contactCount: 3, fnPressed: true))
    }
    func testFnReleaseCancelsUntilAllFingersLift() {
        var gate = FnActivationGate()
        XCTAssertTrue(gate.allowsFrame(contactCount: 3, fnPressed: true))
        XCTAssertFalse(gate.allowsFrame(contactCount: 3, fnPressed: false))
        XCTAssertFalse(gate.allowsFrame(contactCount: 3, fnPressed: true))
        XCTAssertFalse(gate.allowsFrame(contactCount: 0, fnPressed: true))
        XCTAssertTrue(gate.allowsFrame(contactCount: 3, fnPressed: true))
    }
    func testReleaseBetweenContactFramesCanCancelSequence() {
        var gate = FnActivationGate()
        XCTAssertTrue(gate.allowsFrame(contactCount: 3, fnPressed: true))
        gate.cancel()
        XCTAssertFalse(gate.allowsFrame(contactCount: 3, fnPressed: true))
        XCTAssertFalse(gate.allowsFrame(contactCount: 0, fnPressed: true))
    }
    func testTurningRequirementOffAllowsAnUnmodifiedNewGesture() {
        var gate = FnActivationGate()
        XCTAssertTrue(gate.allowsFrame(contactCount: 3, fnPressed: false, requiresFn: false))
        XCTAssertTrue(gate.allowsFrame(contactCount: 0, fnPressed: false, requiresFn: false))
    }
    func testChangingRequirementMidGestureCancelsIt() {
        var gate = FnActivationGate()
        XCTAssertTrue(gate.allowsFrame(contactCount: 3, fnPressed: true))
        XCTAssertFalse(gate.allowsFrame(contactCount: 3, fnPressed: false, requiresFn: false))
        XCTAssertFalse(gate.allowsFrame(contactCount: 0, fnPressed: false, requiresFn: false))
        XCTAssertTrue(gate.allowsFrame(contactCount: 3, fnPressed: false, requiresFn: false))
    }
    func testDevicesRemainIndependent() {
        var first = FnActivationGate(), second = FnActivationGate()
        XCTAssertTrue(first.allowsFrame(contactCount: 3, fnPressed: true))
        XCTAssertFalse(second.allowsFrame(contactCount: 3, fnPressed: false))
        XCTAssertTrue(first.allowsFrame(contactCount: 0, fnPressed: true))
    }
    func testRuntimeFnFlagAPIIsAvailable() {
        let flags: CGEventFlags = .maskSecondaryFn
        XCTAssertTrue(flags.contains(.maskSecondaryFn))
        _ = CGEventSource.flagsState(.hidSystemState)
    }
}
