import XCTest
import NiceTouchCore
import TrackpadBridge
@testable import NiceTouch

@MainActor private final class RuntimeFixture {
    var app = "com.google.Chrome"
    var trusted = true
    var fn = true
    var captureSucceeds = true
    var starts = 0
    var stops = 0
    var actions: [RuleAction] = []
    var callback: NTFrameCallback?
    var services: RuntimeServices {
        var value = RuntimeServices()
        value.hasAccessibility = { self.trusted }
        value.fnHeld = { self.fn }
        value.activeApp = { self.app }
        value.startCapture = { callback in self.starts += 1; self.callback = callback; return self.captureSucceeds }
        value.stopCapture = { self.stops += 1 }
        value.actionHandler = { action in self.actions.append(action); return true }
        value.installObservers = false
        return value
    }
    func emit(count: Int, x: Float, time: Double) {
        let xs = Array(repeating: x, count: max(1, count)), ys = Array(repeating: Float(0.5), count: max(1, count))
        xs.withUnsafeBufferPointer { xBuffer in
            ys.withUnsafeBufferPointer { yBuffer in callback?(1, xBuffer.baseAddress, yBuffer.baseAddress, Int32(count), time) }
        }
    }
}

@MainActor final class RuntimeEngineTests: XCTestCase {
    func rule(app: String = "com.google.Chrome") -> SavedRule {
        SavedRule(definition: RuleDefinition(name: "Copy", app: app, gesture: Gesture(kind: .swipe, fingers: 3, direction: .left), action: .copy))
    }
    func frame(_ engine: RuntimeEngine, x: Double, time: Double, fn: Bool = true) {
        engine.feed(device: 1, contacts: Array(repeating: Contact(x: x, y: 0.5), count: 3), time: time, fnPressed: fn)
    }
    func swipe(_ engine: RuntimeEngine, at time: Double) {
        frame(engine, x: 0.8, time: time)
        frame(engine, x: 0.4, time: time + 0.1)
        engine.feed(device: 1, contacts: [], time: time + 0.2, fnPressed: true)
    }
    func drainDeliveries() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
    func testOneActionPerSequenceAndCooldown() throws {
        let fixture = RuntimeFixture()
        let runtime = RuntimeEngine(services: fixture.services); runtime.rules = [rule()]
        try runtime.start(); defer { runtime.stop() }
        swipe(runtime, at: 0)
        runtime.feed(device: 1, contacts: [], time: 0.21, fnPressed: true)
        XCTAssertEqual(fixture.actions, [.copy])
        swipe(runtime, at: 0.25); XCTAssertEqual(fixture.actions, [.copy])
        swipe(runtime, at: 1); XCTAssertEqual(fixture.actions, [.copy, .copy])
    }
    func testFnMustBeHeldFromFirstContactThroughExecution() throws {
        let fixture = RuntimeFixture()
        let runtime = RuntimeEngine(services: fixture.services); runtime.rules = [rule()]
        try runtime.start(); defer { runtime.stop() }
        frame(runtime, x: 0.8, time: 0, fn: false)
        frame(runtime, x: 0.4, time: 0.1)
        runtime.feed(device: 1, contacts: [], time: 0.2, fnPressed: true)
        XCTAssertTrue(fixture.actions.isEmpty)
        frame(runtime, x: 0.8, time: 1)
        frame(runtime, x: 0.4, time: 1.1, fn: false)
        runtime.feed(device: 1, contacts: [], time: 1.2, fnPressed: true)
        XCTAssertTrue(fixture.actions.isEmpty)
        swipe(runtime, at: 2); XCTAssertEqual(fixture.actions, [.copy])
    }
    func testPhysicalFnStateIsRecheckedAtDispatch() throws {
        let fixture = RuntimeFixture()
        let engine = RuntimeEngine(services: fixture.services); engine.rules = [rule()]
        try engine.start(); defer { engine.stop() }
        fixture.fn = false
        swipe(engine, at: 0)
        XCTAssertTrue(fixture.actions.isEmpty)
        fixture.fn = true
        swipe(engine, at: 1); XCTAssertEqual(fixture.actions, [.copy])
    }
    func testSwitchingAppsCancelsGlobalRuleEvenAfterSwitchingBack() throws {
        let fixture = RuntimeFixture()
        let runtime = RuntimeEngine(services: fixture.services); runtime.rules = [rule(app: "*")]
        try runtime.start(); defer { runtime.stop() }
        frame(runtime, x: 0.8, time: 0)
        fixture.app = "com.apple.Safari"; frame(runtime, x: 0.4, time: 0.1)
        fixture.app = "com.google.Chrome"
        runtime.feed(device: 1, contacts: [], time: 0.2, fnPressed: true)
        XCTAssertTrue(fixture.actions.isEmpty)
        frame(runtime, x: 0.8, time: 1)
        runtime.cancelForAppSwitch()
        frame(runtime, x: 0.4, time: 1.1)
        runtime.feed(device: 1, contacts: [], time: 1.2, fnPressed: true)
        XCTAssertTrue(fixture.actions.isEmpty)
        swipe(runtime, at: 2); XCTAssertEqual(fixture.actions, [.copy])
    }
    func testPermissionRevocationStopsBeforeAction() throws {
        let fixture = RuntimeFixture()
        let engine = RuntimeEngine(services: fixture.services); engine.rules = [rule()]
        try engine.start(); fixture.trusted = false
        swipe(engine, at: 0)
        XCTAssertFalse(engine.running); XCTAssertTrue(fixture.actions.isEmpty)
        XCTAssertEqual(fixture.stops, 1)
        engine.stop(); XCTAssertEqual(fixture.stops, 1)
    }
    func testAmbiguousRulesNeverDispatch() throws {
        let fixture = RuntimeFixture()
        let engine = RuntimeEngine(services: fixture.services); engine.rules = [rule(), rule()]
        try engine.start(); defer { engine.stop() }
        swipe(engine, at: 0); XCTAssertTrue(fixture.actions.isEmpty)
    }
    func testRestartClearsPartialGestures() throws {
        let fixture = RuntimeFixture()
        let engine = RuntimeEngine(services: fixture.services); engine.rules = [rule()]
        try engine.start()
        frame(engine, x: 0.8, time: 0)
        engine.stop(); try engine.start(); defer { engine.stop() }
        frame(engine, x: 0.4, time: 0.1)
        engine.feed(device: 1, contacts: [], time: 0.2, fnPressed: true)
        XCTAssertTrue(fixture.actions.isEmpty)
        swipe(engine, at: 1); XCTAssertEqual(fixture.actions, [.copy])
    }
    func testCDrawingLaunchUsesTheSameFnGate() throws {
        let fixture = RuntimeFixture()
        let engine = RuntimeEngine(services: fixture.services)
        engine.rules = [SavedRule(definition: RuleDefinition(name: "Open Codex", app: "*", gesture: Gesture(kind: .drawC, fingers: 1, direction: .none), action: .openCodex))]
        try engine.start(); defer { engine.stop() }
        func draw(at start: Double, releaseFn: Bool) {
            for index in 0...48 {
                let angle = Double.pi / 4 + Double(index) / 48 * 1.5 * Double.pi
                engine.feed(device: 1, contacts: [Contact(x: 0.5 + 0.25 * cos(angle), y: 0.5 + 0.3 * sin(angle))],
                            time: start + Double(index) / 50, fnPressed: !(releaseFn && index == 20))
            }
            engine.feed(device: 1, contacts: [], time: start + 1, fnPressed: true)
        }
        draw(at: 0, releaseFn: true); XCTAssertTrue(fixture.actions.isEmpty)
        draw(at: 2, releaseFn: false); XCTAssertEqual(fixture.actions, [.openCodex])
    }
    func testFailedCaptureAndDeniedPermissionDoNotRun() throws {
        let fixture = RuntimeFixture(); fixture.captureSucceeds = false
        let engine = RuntimeEngine(services: fixture.services); engine.rules = [rule()]
        XCTAssertThrowsError(try engine.start()); XCTAssertFalse(engine.running)
        swipe(engine, at: 0); XCTAssertTrue(fixture.actions.isEmpty)
        fixture.trusted = false
        XCTAssertThrowsError(try engine.start()); XCTAssertEqual(fixture.starts, 1)
    }
    func testQueuedFramesFromPreviousSessionCannotTriggerAfterRestart() async throws {
        let fixture = RuntimeFixture()
        let engine = RuntimeEngine(services: fixture.services); engine.requireFn = false; engine.rules = [rule()]
        try engine.start()
        fixture.emit(count: 3, x: 0.8, time: 0)
        fixture.emit(count: 3, x: 0.4, time: 0.1)
        fixture.emit(count: 0, x: 0, time: 0.2)
        engine.stop(); try engine.start(); defer { engine.stop() }
        await drainDeliveries()
        XCTAssertTrue(fixture.actions.isEmpty, "Queued pre-pause frames must not reach the new session")
        fixture.emit(count: 3, x: 0.8, time: 1)
        fixture.emit(count: 3, x: 0.4, time: 1.1)
        fixture.emit(count: 0, x: 0, time: 1.2)
        await drainDeliveries()
        XCTAssertEqual(fixture.actions, [.copy])
    }
    func testInactiveEngineCannotStopTheCurrentSession() async throws {
        let a = RuntimeFixture(), b = RuntimeFixture()
        let first = RuntimeEngine(services: a.services), second = RuntimeEngine(services: b.services)
        first.rules = [rule()]; second.rules = [rule()]; second.requireFn = false
        try first.start(); try second.start(); defer { second.stop() }
        XCTAssertFalse(first.running); XCTAssertTrue(second.running); XCTAssertEqual(a.stops, 1)
        first.stop(); XCTAssertEqual(b.stops, 0)
        b.emit(count: 3, x: 0.8, time: 0)
        b.emit(count: 3, x: 0.4, time: 0.1)
        b.emit(count: 0, x: 0, time: 0.2)
        await drainDeliveries()
        XCTAssertEqual(b.actions, [.copy]); XCTAssertTrue(a.actions.isEmpty)
    }
}
