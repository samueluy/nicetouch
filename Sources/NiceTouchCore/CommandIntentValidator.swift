import Foundation

public enum CommandIntentError: LocalizedError, Equatable {
    case clarification(String)
    case mismatch(String)
    public var errorDescription: String? {
        switch self { case .clarification(let value), .mismatch(let value): return value }
    }
}
/// Guard model output against facts the user supplied. This does not create
/// rules; the selected model still interprets and generates each complete rule.
public enum CommandIntentValidator {
    private static let appAliases: [String: [String]] = [
        "com.google.Chrome": ["Chrome", "Google Chrome"], "com.apple.Safari": ["Safari"],
        "org.mozilla.firefox": ["Firefox"], "com.apple.dt.Xcode": ["Xcode"],
        "com.microsoft.VSCode": ["VSCode", "VS Code", "Visual Studio Code"]
    ]
    private static func text(_ value: String) -> String {
        value.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func has(_ pattern: String, in value: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    private static func mentions(_ phrase: String, in command: String) -> Bool {
        let phrase = text(phrase)
        return !phrase.isEmpty && has("\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b", in: command)
    }
    private static func fingerCounts(_ command: String) -> Set<Int> {
        var counts = Set<Int>()
        if has(#"\b(?:3|three)\s+(?:or|and)\s+(?:4|four)\s*fingers?\b|\b(?:4|four)\s+(?:or|and)\s+(?:3|three)\s*fingers?\b"#, in: command) { return [3, 4] }
        if has(#"\b(?:3|three)\s*fingers?\b|\bfingers?\s*(?:count\s*)?(?:of\s*)?(?:3|three)\b"#, in: command) { counts.insert(3) }
        if has(#"\b(?:4|four)\s*fingers?\b|\bfingers?\s*(?:count\s*)?(?:of\s*)?(?:4|four)\b"#, in: command) { counts.insert(4) }
        return counts
    }
    private static func swipeMentioned(_ command: String) -> Bool {
        has(#"\b(?:swipe|swipes|swiping|swiped|slide|slides|sliding|sweep|sweeping|flick|flicking)\b"#, in: command)
    }
    private static func tapMentioned(_ command: String) -> Bool { has(#"\b(?:tap|taps|tapping|tapped|touch|touching)\b"#, in: command) }
    private static func allApps(_ command: String) -> Bool {
        has(#"\b(?:all|every|any)\s+(?:apps?|applications?|programs?)\b|\bglobally\b|\bsystem wide\b"#, in: command)
    }
    private static func directionText(_ command: String) -> String {
        command.replacingOccurrences(of: #"\b(?:the\s+)?(?:left|right|top|bottom|upper|lower)\s+(?:edge|zone|side|corner)\b"#, with: " ", options: .regularExpression)
    }
    private static func directions(_ command: String) -> Set<Direction> {
        let command = directionText(command)
        var result = Set<Direction>()
        if has(#"\bleft(?:ward|wards)?\b"#, in: command) { result.insert(.left) }
        if has(#"\bright(?:ward|wards)?\b"#, in: command) { result.insert(.right) }
        if has(#"\bup(?:ward|wards)?\b|\btowards?\s+(?:the\s+)?(?:top|menu bar)\b"#, in: command) { result.insert(.up) }
        if has(#"\bdown(?:ward|wards)?\b|\btowards?\s+(?:the\s+)?bottom\b"#, in: command) { result.insert(.down) }
        return result
    }
    private static func actions(_ command: String) -> Set<RuleAction> {
        var result = Set<RuleAction>()
        if has(#"\b(?:copy|copying|copied|copies)\b"#, in: command) { result.insert(.copy) }
        if has(#"\b(?:paste|pasting|pasted)\b"#, in: command) { result.insert(.paste) }
        if has(#"\b(?:undo|undoing)\b|\brevert\s+(?:the\s+)?(?:last|previous)\s+change\b"#, in: command) { result.insert(.undo) }
        if has(#"\b(?:redo|redoing)\b|\breapply\s+(?:the\s+)?(?:last|previous)\s+change\b"#, in: command) { result.insert(.redo) }
        let reopened = has(#"\b(?:reopen|reopening|restore|recover)\b.*\btab\b|\bbring\b.*\bback\b.*\btab\b"#, in: command)
        if reopened { result.insert(.reopenTab) }
        if has(#"\b(?:close|closing)\b(?:\s+\w+){0,3}\s+tabs?\b"#, in: command) { result.insert(.closeTab) }
        if !reopened {
            if has(#"\b(?:previous|prev|preceding|earlier|back|backward|backwards)\b(?:\s+\w+){0,2}\s+tabs?\b|\btabs?\s+(?:back|backward|backwards)\b"#, in: command) { result.insert(.previousTab) }
        }
        if has(#"\b(?:next|following|forward|forwards)\b(?:\s+\w+){0,2}\s+tabs?\b|\btabs?\s+(?:forward|forwards|ahead)\b"#, in: command) { result.insert(.nextTab) }
        if has(#"\b(?:open|launch|show|activate|focus)\b.*\bchat\s?gpt\b"#, in: command) { result.insert(.openChatGPT) }
        if has(#"\b(?:open|launch|show|activate|focus)\b.*\bcodex\b"#, in: command) { result.insert(.openCodex) }
        return result
    }
    private static func drawingC(_ command: String) -> Bool {
        has(#"\b(?:draw|drawing|trace|tracing)\s+(?:(?:a|the|letter)\s+){0,2}c\b|\bc shaped\b"#, in: command)
    }
    private static func sourceAppMentioned(_ command: String, knownApps: [String: String]) -> Bool {
        let names = appAliases.values.flatMap { $0 } + Array(knownApps.values) + Array(knownApps.keys)
        if has(#"\b(?:in|inside|within)\s+(?!(?:all|every|any)\s+(?:apps?|applications?))(?!(?:the\s+)?(?:top|bottom|left|right)\s+(?:zone|edge|side))"#, in: command) { return true }
        return names.contains { name in
            has("\\b(?:in|inside|within|using)\\s+(?:the\\s+)?" + NSRegularExpression.escapedPattern(for: text(name)) + "\\b", in: command)
        }
    }
    public static func clarification(for command: String) -> String? {
        let command = text(command), counts = fingerCounts(command)
        let drawing = drawingC(command)
        if drawing {
            if !counts.isEmpty || has(#"\b(?:0|[2-9]|[1-9][0-9]+|zero|two|five|six|seven|eight|nine)\s*fingers?\b"#, in: command) { return "Draw C with one finger. Swipes and taps use three or four fingers." }
        } else {
            if has(#"\b(?:draw|drawing|trace|tracing)\b"#, in: command) { return "C is the supported drawing gesture. Draw it with one finger, or use a three- or four-finger swipe or tap." }
            guard !counts.isEmpty else { return "Use three or four fingers. Which gesture, app and action should they trigger?" }
            guard counts.count == 1 else { return "Choose one finger count for this rule: three or four." }
        }
        let swipe = swipeMentioned(command), tap = tapMentioned(command)
        guard swipe || tap || drawing else { return "Should this be a swipe, a tap or a C drawing?" }
        guard [swipe, tap, drawing].filter({ $0 }).count == 1 else { return "Choose one gesture for this rule: a swipe, a tap or a C drawing." }
        if swipe && directions(command).count != 1 { return "Which direction should the swipe use: left, right, up or down?" }
        if has(#"\b(?:script|scripts|shell|applescript|javascript|python|terminal command)\b"#, in: command) {
            return "Scripts are not supported. Choose a tab action, copy, paste, undo, redo, Open ChatGPT or Open Codex."
        }
        let supported = actions(command)
        if supported.isEmpty { return "Choose an action: previous tab, next tab, close tab, reopen tab, copy, paste, undo, redo, Open ChatGPT or Open Codex." }
        if supported.count > 1 { return "Choose one action for this gesture. Create a separate rule for another action." }
        return nil
    }
    public static func validate(_ rule: RuleDefinition, command: String, knownApps: [String: String] = [:]) throws {
        if let question = clarification(for: command) { throw CommandIntentError.clarification(question) }
        let command = text(command)
        if drawingC(command) {
            guard rule.gesture.kind == .drawC, rule.gesture.fingers == 1 else { throw CommandIntentError.mismatch("Use drawC with one finger for the requested C drawing.") }
        } else {
            guard fingerCounts(command).contains(rule.gesture.fingers) else { throw CommandIntentError.mismatch("Use the finger count stated in the command.") }
            guard rule.gesture.kind == .swipe ? swipeMentioned(command) : tapMentioned(command) else { throw CommandIntentError.mismatch("Use the gesture type stated in the command.") }
        }
        if rule.gesture.kind == .swipe && !directions(command).contains(rule.gesture.direction) { throw CommandIntentError.mismatch("Use the swipe direction stated in the command.") }
        guard actions(command).contains(rule.action) else { throw CommandIntentError.mismatch("Use the requested action; do not substitute another supported action.") }
        if allApps(command) || (rule.action.launchBundleIdentifier != nil && !sourceAppMentioned(command, knownApps: knownApps)) {
            guard rule.app == "*" else { throw CommandIntentError.mismatch("The user requested all apps. Set app to * instead of a specific app.") }
        } else {
            guard rule.app != "*" else { throw CommandIntentError.clarification("Which app should use this gesture? Use all apps if you want a global rule.") }
            let candidates = (appAliases[rule.app] ?? []) + [rule.app, rule.app.components(separatedBy: ".").last ?? ""] + [knownApps[rule.app]].compactMap { $0 }
            if !candidates.contains(where: { mentions($0, in: command) }) {
                let otherNames = appAliases.values.flatMap { $0 } + Array(knownApps.values)
                if otherNames.contains(where: { mentions($0, in: command) }) {
                    throw CommandIntentError.mismatch("Use the app named in the command, not a different app from the context.")
                }
                throw CommandIntentError.clarification("Which app should use this gesture? Include its name, bundle ID or all apps.")
            }
        }
        let zoneWords: [(Zone, String)] = [(.left, "left"), (.right, "right"), (.top, "(?:top|upper)"), (.bottom, "(?:bottom|lower)")]
        let requested = zoneWords.filter { has("\\b" + $0.1 + #"\s+(?:edge|zone|side|corner)\b"#, in: command) }.map(\.0)
        if let zone = requested.first, requested.count == 1, rule.gesture.zone != zone {
            throw CommandIntentError.mismatch("Use the \(zone.rawValue) zone requested by the user.")
        }
        if requested.isEmpty && rule.gesture.zone != .anywhere {
            throw CommandIntentError.mismatch("No edge zone was requested. Set zone to anywhere.")
        }
    }
}
