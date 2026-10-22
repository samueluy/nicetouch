import Foundation

public struct Contact: Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
public struct RecognizedGesture: Sendable {
    public let gesture: Gesture
    public let x: Double
    public let y: Double
}
/// One independent recognizer per device. Emit at most once, after every contact lifts.
public struct GestureRecognizer {
    private var cShape = CShapeRecognizer()
    private var start: Contact?
    private var count = 0
    private var began = 0.0
    private var dx = 0.0, dy = 0.0, travel = 0.0
    private var invalid = false
    private var lifting = false
    public init() {}
    public mutating func reset() { self = GestureRecognizer() }
    public mutating func feed(_ contacts: [Contact], time: Double) -> RecognizedGesture? {
        let drawing = cShape.feed(contacts, time: time)
        return feedStandard(contacts, time: time) ?? drawing
    }
    private mutating func feedStandard(_ contacts: [Contact], time: Double) -> RecognizedGesture? {
        guard time.isFinite, contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            let drawing = cShape
            reset(); cShape = drawing
            return nil
        }
        if contacts.isEmpty {
            defer { reset() }
            guard let start, !invalid, time >= began, time - began < 1.2 else { return nil }
            let direction: Direction
            let kind: GestureKind
            if travel < 0.035 && time - began <= 0.3 { kind = .tap; direction = .none }
            else if max(abs(dx), abs(dy)) >= 0.18 && max(abs(dx), abs(dy)) > min(abs(dx), abs(dy)) * 1.5 {
                kind = .swipe
                direction = abs(dx) > abs(dy) ? (dx < 0 ? .left : .right) : (dy < 0 ? .down : .up)
            } else { return nil }
            return RecognizedGesture(gesture: Gesture(kind: kind, fingers: count, direction: direction), x: start.x, y: start.y)
        }
        if start == nil {
            guard [3, 4].contains(contacts.count) else { return nil }
            start = centroid(contacts); count = contacts.count; began = time
        }
        guard let start else { return nil }
        if time < began || contacts.count > count { invalid = true }
        if contacts.count < count { lifting = true; return nil }
        if lifting { invalid = true; return nil }
        let p = centroid(contacts)
        let x = p.x - start.x, y = p.y - start.y
        travel = max(travel, hypot(x, y))
        if max(abs(x), abs(y)) > max(abs(dx), abs(dy)) { dx = x; dy = y }
        return nil
    }
    private func centroid(_ c: [Contact]) -> Contact {
        Contact(x: c.map(\.x).reduce(0, +) / Double(c.count), y: c.map(\.y).reduce(0, +) / Double(c.count))
    }
}
public enum RuleMatcher {
    /// Ambiguous configuration fails closed even if a caller bypasses collection validation.
    public static func match(_ event: RecognizedGesture, app: String, rules: [SavedRule]) -> SavedRule? {
        let matches = rules.filter { r in
            r.enabled && (r.definition.app == "*" || r.definition.app == app)
                && r.definition.gesture.kind == event.gesture.kind && r.definition.gesture.fingers == event.gesture.fingers
                && r.definition.gesture.direction == event.gesture.direction
                && r.definition.gesture.zone.contains(x: event.x, y: event.y)
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
