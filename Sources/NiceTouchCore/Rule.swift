import Foundation

public enum GestureKind: String, Codable, CaseIterable, Sendable { case swipe, tap }
public enum Direction: String, Codable, CaseIterable, Sendable { case left, right, up, down, none }
public enum Zone: String, Codable, CaseIterable, Sendable {
    case anywhere, left, right, top, bottom
    public func contains(x: Double, y: Double) -> Bool {
        switch self {
        case .anywhere: return true
        case .left: return x < 0.25
        case .right: return x > 0.75
        case .top: return y > 0.75
        case .bottom: return y < 0.25
        }
    }
    public func overlaps(_ other: Zone) -> Bool {
        if self == .anywhere || other == .anywhere || self == other { return true }
        return !((self == .left && other == .right) || (self == .right && other == .left)
            || (self == .top && other == .bottom) || (self == .bottom && other == .top))
    }
}
public enum RuleAction: String, Codable, CaseIterable, Sendable {
    case previousTab, nextTab, closeTab, reopenTab, copy, paste, undo, redo
    public var label: String {
        switch self {
        case .previousTab: return "Previous tab"
        case .nextTab: return "Next tab"
        case .closeTab: return "Close tab"
        case .reopenTab: return "Reopen closed tab"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .undo: return "Undo"
        case .redo: return "Redo"
        }
    }
}
public struct Gesture: Codable, Equatable, Sendable {
    public var kind: GestureKind
    public var fingers: Int
    public var direction: Direction
    public var zone: Zone
    public init(kind: GestureKind, fingers: Int, direction: Direction, zone: Zone = .anywhere) {
        self.kind = kind; self.fingers = fingers; self.direction = direction; self.zone = zone
    }
    public var label: String {
        "\(fingers)-finger \(kind.rawValue)" + (direction == .none ? "" : " \(direction.rawValue)")
    }
    public var symbol: String {
        if kind == .tap { return "hand.tap" }
        return "arrow." + (direction == .up ? "up" : direction == .down ? "down" : direction.rawValue)
    }
}
public struct RuleDefinition: Codable, Equatable, Sendable {
    public var version: Int
    public var name: String
    public var app: String
    public var gesture: Gesture
    public var action: RuleAction
    public init(name: String, app: String, gesture: Gesture, action: RuleAction) {
        version = 1; self.name = name; self.app = app; self.gesture = gesture; self.action = action
    }
    public var appLabel: String { app == "*" ? "All apps" : app.components(separatedBy: ".").last ?? app }
    public var json: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? ""
    }
}
public struct SavedRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var enabled: Bool
    public var definition: RuleDefinition
    public init(id: UUID = UUID(), enabled: Bool = true, definition: RuleDefinition) {
        self.id = id; self.enabled = enabled; self.definition = definition
    }
}
public struct RuleError: LocalizedError, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public enum RuleValidator {
    public static func parse(_ text: String) throws -> RuleDefinition {
        guard text.utf8.count <= 16_384, let data = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RuleError("Return one JSON object under 16 KB, without Markdown or commentary.")
        }
        try JSONKeyAudit.validate(data)
        try keys(object, expected: ["version", "name", "app", "gesture", "action"])
        guard let gesture = object["gesture"] as? [String: Any] else { throw RuleError("gesture must be an object.") }
        try keys(gesture, expected: ["kind", "fingers", "direction", "zone"])
        let rule: RuleDefinition
        do { rule = try JSONDecoder().decode(RuleDefinition.self, from: data) }
        catch { throw RuleError("Use the schema's exact types and allowed gesture, direction, zone, and action values.") }
        try validate(rule)
        return rule
    }
    private static func keys(_ object: [String: Any], expected: Set<String>) throws {
        guard Set(object.keys) == expected else { throw RuleError("Required keys: \(expected.sorted().joined(separator: ", ")). Extra or missing fields are not allowed.") }
        guard !object.values.contains(where: { $0 is NSNull }) else { throw RuleError("Null fields are not allowed.") }
    }
    public static func validate(_ rule: RuleDefinition) throws {
        guard rule.version == 1 else { throw RuleError("Only schema version 1 is supported.") }
        guard (1...80).contains(rule.name.count), rule.name == rule.name.trimmingCharacters(in: .whitespacesAndNewlines),
              !rule.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw RuleError("Use a short name of 1–80 characters without surrounding whitespace or control characters.")
        }
        guard rule.app == "*" || (rule.app.count <= 200 && rule.app.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil) else {
            throw RuleError("Use * for all apps or an exact app bundle identifier, such as com.google.Chrome.")
        }
        guard [3, 4].contains(rule.gesture.fingers) else { throw RuleError("Choose three or four fingers.") }
        guard (rule.gesture.kind == .tap) == (rule.gesture.direction == .none) else {
            throw RuleError("Taps require direction none; swipes require left, right, up, or down.")
        }
    }
    public static func conflicts(_ candidate: RuleDefinition, with rules: [SavedRule], excluding: UUID? = nil) -> [SavedRule] {
        rules.filter { saved in
            let r = saved.definition
            return saved.enabled && saved.id != excluding && (candidate.app == "*" || r.app == "*" || candidate.app == r.app)
                && candidate.gesture.kind == r.gesture.kind && candidate.gesture.fingers == r.gesture.fingers
                && candidate.gesture.direction == r.gesture.direction && candidate.gesture.zone.overlaps(r.gesture.zone)
        }
    }
    public static func validateCollection(_ rules: [SavedRule]) throws {
        guard rules.count <= 500, Set(rules.map(\.id)).count == rules.count else { throw RuleError("Rule file has duplicate IDs or more than 500 rules.") }
        for r in rules {
            try validate(r.definition)
            if r.enabled && !conflicts(r.definition, with: rules, excluding: r.id).isEmpty { throw RuleError("Conflicting enabled rules: \(r.definition.name). Disable one before enabling the other.") }
        }
    }
}
public enum Samples {
    public static let rules: [SavedRule] = [
        SavedRule(enabled: false, definition: RuleDefinition(name: "Previous tab", app: "com.google.Chrome", gesture: Gesture(kind: .swipe, fingers: 3, direction: .left), action: .previousTab)),
        SavedRule(enabled: false, definition: RuleDefinition(name: "Next tab", app: "com.google.Chrome", gesture: Gesture(kind: .swipe, fingers: 3, direction: .right), action: .nextTab)),
        SavedRule(enabled: false, definition: RuleDefinition(name: "Reopen closed tab", app: "*", gesture: Gesture(kind: .tap, fingers: 4, direction: .none, zone: .top), action: .reopenTab))
    ]
}
