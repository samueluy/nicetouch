import XCTest
@testable import NiceTouchCore

final class CShapeTests: XCTestCase {
    func arc(start: Double = .pi / 4, sweep: Double = 1.5 * .pi, mirror: Bool = false) -> [Contact] {
        (0...48).map { index in
            let angle = start + Double(index) / 48 * sweep
            return Contact(x: 0.5 + (mirror ? -1 : 1) * 0.25 * cos(angle), y: 0.5 + 0.3 * sin(angle))
        }
    }
    func recognize(_ path: [Contact], duration: Double = 1, fingers: Int = 1) -> RecognizedGesture? {
        var recognizer = GestureRecognizer()
        for (index, point) in path.enumerated() {
            XCTAssertNil(recognizer.feed(Array(repeating: point, count: fingers), time: Double(index) / Double(path.count) * duration))
        }
        return recognizer.feed([], time: duration)
    }
    func testCRecognizesBothStrokeDirections() {
        for path in [arc(), Array(arc().reversed())] {
            let event = recognize(path)
            XCTAssertEqual(event?.gesture, Gesture(kind: .drawC, fingers: 1, direction: .none))
            XCTAssertEqual(event?.x, path.first?.x)
        }
    }
    func testTranslatedScaledAndNoisyC() {
        let path = arc().enumerated().map { index, point in
            Contact(x: point.x * 0.7 + 0.03 + sin(Double(index)) * 0.004, y: point.y * 0.8 + 0.1)
        }
        XCTAssertEqual(recognize(path)?.gesture.kind, .drawC)
    }
    func testLongTraceStaysBoundedAndInvalidInputCancelsUntilLift() {
        let dense = (0...600).map { index -> Contact in
            let angle = Double.pi / 4 + Double(index) / 600 * 1.5 * Double.pi
            return Contact(x: 0.5 + 0.3 * cos(angle), y: 0.5 + 0.3 * sin(angle))
        }
        XCTAssertEqual(recognize(dense, duration: 2.5)?.gesture.kind, .drawC)
        var recognizer = GestureRecognizer()
        _ = recognizer.feed([Contact(x: .nan, y: 0.5)], time: 0)
        for (index, point) in arc().enumerated() { _ = recognizer.feed([point], time: 0.1 + Double(index) / 50) }
        XCTAssertNil(recognizer.feed([], time: 1.2))
    }
    func testCircleMirroredCAndOtherShapesDoNotLaunch() {
        for path in [arc(start: 0, sweep: 2 * .pi), arc(mirror: true), arc(start: .pi, sweep: .pi), (0...30).map({ Contact(x: 0.2 + Double($0) / 60, y: 0.5) }), (0...30).map({ Contact(x: 0.3 + Double($0 % 2) * 0.4, y: 0.2 + Double($0) / 60) })] {
            XCTAssertNil(recognize(path))
        }
    }
    func testTooSmallSlowOrMultifingerCRejected() {
        XCTAssertNil(recognize(arc().map { Contact(x: $0.x * 0.1, y: $0.y * 0.1) }))
        XCTAssertNil(recognize(arc(), duration: 4))
        XCTAssertNil(recognize(arc(), fingers: 2))
        XCTAssertNil(recognize(arc(), duration: 0.1))
    }
    func testSecondFingerCancelsUntilLift() {
        var recognizer = GestureRecognizer()
        let path = arc()
        for (index, point) in path.enumerated() {
            _ = recognizer.feed(Array(repeating: point, count: index == 10 ? 2 : 1), time: Double(index) / 50)
        }
        XCTAssertNil(recognizer.feed([], time: 1))
        for (index, point) in path.enumerated() { _ = recognizer.feed([point], time: 2 + Double(index) / 50) }
        XCTAssertEqual(recognizer.feed([], time: 3)?.gesture.kind, .drawC)
    }
    func testSingleContactBeforeThreeFingerSwipeStillWorks() {
        var recognizer = GestureRecognizer()
        _ = recognizer.feed([Contact(x: 0.8, y: 0.5)], time: 0)
        _ = recognizer.feed(Array(repeating: Contact(x: 0.8, y: 0.5), count: 3), time: 0.01)
        _ = recognizer.feed(Array(repeating: Contact(x: 0.4, y: 0.5), count: 3), time: 0.2)
        XCTAssertEqual(recognizer.feed([], time: 0.3)?.gesture, Gesture(kind: .swipe, fingers: 3, direction: .left))
    }
    func testInvalidCoordinatesAndResetCannotCompleteC() {
        var recognizer = GestureRecognizer()
        let path = arc()
        for (index, point) in path.enumerated() {
            _ = recognizer.feed([point], time: Double(index) / 50)
            if index == 25 { recognizer.reset() }
        }
        XCTAssertNil(recognizer.feed([], time: 1))
        XCTAssertNil(recognizer.feed([Contact(x: .nan, y: 0.5)], time: 2))
    }
}
