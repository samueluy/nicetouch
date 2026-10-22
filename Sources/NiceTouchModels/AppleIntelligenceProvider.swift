import Foundation
import FoundationModels

@available(macOS 26.0, *)
@Generable enum AppleFingerCount { case three, four
    var value: Int { self == .three ? 3 : 4 }
}
@available(macOS 26.0, *)
@Generable enum AppleSwipeDirection: String { case left, right, up, down }
@available(macOS 26.0, *)
@Generable enum AppleZone: String { case anywhere, left, right, top, bottom }
@available(macOS 26.0, *)
@Generable enum AppleAction: String { case previousTab, nextTab, closeTab, reopenTab, copy, paste, undo, redo, openChatGPT, openCodex }
@available(macOS 26.0, *)
@Generable enum AppleGesture {
    case swipe(fingers: AppleFingerCount, direction: AppleSwipeDirection, zone: AppleZone)
    case tap(fingers: AppleFingerCount, zone: AppleZone)
    case drawC(zone: AppleZone)
}
@available(macOS 26.0, *)
@Generable enum AppleSourceApp {
    case allApps, chrome, safari, firefox, xcode, vsCode
    case other(bundleIdentifier: String)
    var bundleIdentifier: String {
        switch self {
        case .allApps: return "*"
        case .chrome: return "com.google.Chrome"
        case .safari: return "com.apple.Safari"
        case .firefox: return "org.mozilla.firefox"
        case .xcode: return "com.apple.dt.Xcode"
        case .vsCode: return "com.microsoft.VSCode"
        case .other(let bundleIdentifier): return bundleIdentifier
        }
    }
    init(bundleIdentifier: String) {
        switch bundleIdentifier {
        case "*": self = .allApps
        case "com.google.Chrome": self = .chrome
        case "com.apple.Safari": self = .safari
        case "org.mozilla.firefox": self = .firefox
        case "com.apple.dt.Xcode": self = .xcode
        case "com.microsoft.VSCode": self = .vsCode
        default: self = .other(bundleIdentifier: bundleIdentifier)
        }
    }
}
@available(macOS 26.0, *)
@Generable struct AppleRule {
    @Guide(description: "Short action label, without slogans.") var name: String
    @Guide(description: "Where the gesture works. Choose allApps for global rules and app-opening commands without a named source app. This is not the app to launch.") var app: AppleSourceApp
    var gesture: AppleGesture
    var action: AppleAction
    init(name: String, app: String, gesture: AppleGesture, action: AppleAction) {
        self.name = name; self.app = AppleSourceApp(bundleIdentifier: app); self.gesture = gesture; self.action = action
    }
    func json() throws -> String {
        let gestureObject: [String: Any]
        switch gesture {
        case .swipe(let fingers, let direction, let zone):
            gestureObject = ["kind": "swipe", "fingers": fingers.value, "direction": direction.rawValue, "zone": zone.rawValue]
        case .drawC(let zone):
            gestureObject = ["kind": "drawC", "fingers": 1, "direction": "none", "zone": zone.rawValue]
        case .tap(let fingers, let zone):
            gestureObject = ["kind": "tap", "fingers": fingers.value, "direction": "none", "zone": zone.rawValue]
        }
        let object: [String: Any] = ["version": 1, "name": name, "app": app.bundleIdentifier, "gesture": gestureObject, "action": action.rawValue]
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
    }
}
@available(macOS 26.0, *)
@Generable enum AppleInterpretation {
    case rule(AppleRule)
    case clarification(String)
}
@available(macOS 26.0, *)
public actor AppleIntelligenceProvider: RuleModelProvider {
    public init() {}
    public func readiness() async -> ModelReadiness {
        switch SystemLanguageModel.default.availability {
        case .available: return .ready
        case .unavailable(.appleIntelligenceNotEnabled): return .unavailable("Turn on Apple Intelligence in System Settings to create rules with Apple's model.")
        case .unavailable(.modelNotReady): return .unavailable("Apple's model is not ready. Check Apple Intelligence in System Settings and retry when the download finishes.")
        case .unavailable(.deviceNotEligible): return .unavailable("This Mac does not support Apple Intelligence. Select a custom local model or API provider.")
        case .unavailable: return .unavailable("Apple Intelligence is unavailable on this Mac.")
        @unknown default: return .unavailable("Apple Intelligence is unavailable on this Mac.")
        }
    }
    public func generate(_ request: RuleModelRequest) async throws -> String {
        let status = await readiness()
        guard status.canGenerate else { throw RuleModelError.unavailable(status.message) }
        // SystemLanguageModel.default is the on-device model. Fresh sessions keep
        // unrelated prior commands out of the generation context. No tools or cloud.
        let session = LanguageModelSession(model: .default, instructions: RuleModelInstructions.common)
        let reply = try await session.respond(to: request.prompt(includeLocalContext: true), generating: AppleInterpretation.self,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 600))
        switch reply.content {
        case .rule(let rule): return try rule.json()
        case .clarification(let question):
            guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RuleModelError.malformedReply }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["error": question]), as: UTF8.self)
        }
    }
}
