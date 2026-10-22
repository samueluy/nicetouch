import Foundation
import NiceTouchCore

public struct InvalidRuleModelOutput: LocalizedError {
    public let output: String
    public let suggestion: String
    public var errorDescription: String? { suggestion }
}
public enum RuleAuthoringPipeline {
    /// The app supplies NiceTouchCore.RuleValidator here. Both attempts use the
    /// selected provider; repair must not change the user's privacy choice.
    public static func generate(_ request: RuleModelRequest, provider: any RuleModelProvider,
                                validate: @Sendable (String) throws -> Void) async throws -> String {
        func question(_ value: String) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: ["error": value]), as: UTF8.self)
        }
        if let clarification = CommandIntentValidator.clarification(for: request.command) { return try question(clarification) }
        var feedback = request.feedback
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let input = try RuleModelRequest(command: request.command, feedback: feedback, localAppContext: request.localAppContext, knownApps: request.knownApps)
            let output = try await provider.generate(input)
            if let object = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
               Set(object.keys) == ["error"], let question = object["error"] as? String,
               !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return output }
            do {
                let rule = try RuleValidator.parse(output)
                try CommandIntentValidator.validate(rule, command: request.command, knownApps: request.knownApps)
                try validate(output)
                return output
            }
            catch CommandIntentError.clarification(let clarification) { return try question(clarification) }
            catch {
                feedback = error.localizedDescription
                if attempt == 1 { throw InvalidRuleModelOutput(output: output, suggestion: feedback) }
            }
        }
        throw RuleModelError.malformedReply
    }
}
