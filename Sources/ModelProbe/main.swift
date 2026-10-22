import Foundation
import NiceTouchCore
import NiceTouchModels

@main struct ModelProbe {
    struct Case {
        let command: String
        let app: String?
        let gesture: Gesture?
        let action: RuleAction?
    }
    static func main() async {
        do { try await run() }
        catch { fputs("Model check failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run() async throws {
        let provider = ModelProviderRegistry.systemAppleProvider()
        let status = await provider.readiness()
        print("Apple Intelligence: " + status.message)
        guard status.canGenerate else {
            if CommandLine.arguments.contains("--check-cases") { throw RuleModelError.unavailable(status.message) }
            return
        }
        if CommandLine.arguments.contains("--check-cases") {
            let cases = [
                Case(command: "When I swipe three fingers left in Chrome, switch to the previous tab.", app: "com.google.Chrome", gesture: Gesture(kind: .swipe, fingers: 3, direction: .left), action: .previousTab),
                Case(command: "When I tap four fingers in the top zone in Safari, reopen the closed tab.", app: "com.apple.Safari", gesture: Gesture(kind: .tap, fingers: 4, direction: .none, zone: .top), action: .reopenTab),
                Case(command: "When I swipe four fingers up in all apps, copy.", app: "*", gesture: Gesture(kind: .swipe, fingers: 4, direction: .up), action: .copy),
                Case(command: "Make my trackpad better", app: nil, gesture: nil, action: nil),
                Case(command: "Swipe three fingers in Chrome to switch tabs", app: nil, gesture: nil, action: nil),
                Case(command: "Tap four fingers in Safari to run my script", app: nil, gesture: nil, action: nil),
                Case(command: "When I swipe three fingers left, switch to the previous tab.", app: nil, gesture: nil, action: nil),
                Case(command: "When I swipe three fingers left in Chrome, go to the previous tab and the next tab.", app: nil, gesture: nil, action: nil)
            ]
            var failures = 0
            for item in cases {
                let started = Date()
                let request = try RuleModelRequest(command: item.command, localAppContext: "Chrome=com.google.Chrome; Safari=com.apple.Safari; Notes=com.apple.Notes")
                do {
                    let output = try await RuleAuthoringPipeline.generate(request, provider: provider) { _ = try RuleValidator.parse($0) }
                    let passed: Bool
                    if let app = item.app, let gesture = item.gesture, let action = item.action {
                        let rule = try RuleValidator.parse(output)
                        passed = rule.app == app && rule.gesture == gesture && rule.action == action
                    } else {
                        let object = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: String]
                        passed = object.map { Set($0.keys) == ["error"] && $0["error"]?.isEmpty == false } ?? false
                    }
                    print("\(passed ? "PASS" : "FAIL") (\(String(format: "%.2f", Date().timeIntervalSince(started)))s): \(item.command)\n\(output)")
                    if !passed { failures += 1 }
                } catch {
                    print("FAIL: \(item.command)\n\(error.localizedDescription)"); failures += 1
                }
            }
            if failures > 0 { throw NSError(domain: "ModelProbe", code: failures, userInfo: [NSLocalizedDescriptionKey: "\(failures) live model cases failed."]) }
        } else if CommandLine.arguments.contains("--generate") {
            let request = try RuleModelRequest(command: "When I swipe three fingers left in Chrome, switch to the previous tab.")
            print(try await RuleAuthoringPipeline.generate(request, provider: provider) { _ = try RuleValidator.parse($0) })
        }
    }
}
