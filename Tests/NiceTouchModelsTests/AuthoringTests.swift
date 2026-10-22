import XCTest
import NiceTouchCore
@testable import NiceTouchModels

private actor SequenceProvider: RuleModelProvider {
    let outputs: [String]
    var inputs: [RuleModelRequest] = []
    init(_ outputs: [String]) { self.outputs = outputs }
    func readiness() async -> ModelReadiness { .ready }
    func generate(_ request: RuleModelRequest) async throws -> String {
        inputs.append(request)
        return outputs[min(inputs.count - 1, outputs.count - 1)]
    }
    func requests() -> [RuleModelRequest] { inputs }
}
private actor LocalBackendFixture: CustomLocalModelBackend {
    let fail: Bool
    var apps = ""
    init(fail: Bool = false) { self.fail = fail }
    func load(python: String, model: String) async throws { if fail { throw RuleModelError.unavailable("Load failed") } }
    func unload() async {}
    func generate(command: String, feedback: String, apps: String) async throws -> String { self.apps = apps; return "{}" }
    func context() -> String { apps }
}
private final class SettingsSecretFixture: APISecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var reads = 0
    func secret(account: String) throws -> String? { lock.lock(); defer { lock.unlock() }; reads += 1; return values[account] }
    func setSecret(_ value: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = value }
    func deleteSecret(account: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account) }
    func readCount() -> Int { lock.lock(); defer { lock.unlock() }; return reads }
}
final class AuthoringTests: XCTestCase {
    func definition() -> RuleDefinition {
        RuleDefinition(name: "Previous tab", app: "com.google.Chrome", gesture: Gesture(kind: .swipe, fingers: 3, direction: .left), action: .previousTab)
    }
    func testInvalidOutputRepairsThroughSameProviderUsingRealValidator() async throws {
        let valid = definition().json
        let invalid = valid.replacingOccurrences(of: "previousTab", with: "runScript")
        let provider = SequenceProvider([invalid, valid])
        let request = try RuleModelRequest(command: "Three-finger swipe left in Chrome to go to previous tab")
        let result = try await RuleAuthoringPipeline.generate(request, provider: provider) { _ = try RuleValidator.parse($0) }
        XCTAssertEqual(try RuleValidator.parse(result), definition())
        let calls = await provider.requests()
        XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls[0].command, calls[1].command)
        XCTAssertFalse(calls[1].feedback.isEmpty)
    }
    func testInvalidOutputStopsAfterOneRepairAndKeepsRawText() async throws {
        let provider = SequenceProvider(["{\"unexpected\":true}"])
        do {
            _ = try await RuleAuthoringPipeline.generate(RuleModelRequest(command: "Swipe left with three fingers in Chrome to switch to previous tab"), provider: provider) { _ = try RuleValidator.parse($0) }
            XCTFail("Expected validation failure")
        } catch let error as InvalidRuleModelOutput {
            XCTAssertEqual(error.output, "{\"unexpected\":true}"); XCTAssertFalse(error.suggestion.isEmpty)
        }
        let calls = await provider.requests(); XCTAssertEqual(calls.count, 2)
    }
    func testClarificationDoesNotRetryOrCreateRule() async throws {
        let provider = SequenceProvider(["{\"error\":\"Which gesture and app?\"}"])
        let output = try await RuleAuthoringPipeline.generate(RuleModelRequest(command: "Make the trackpad better"), provider: provider) { _ = try RuleValidator.parse($0) }
        XCTAssertTrue(output.contains("Which gesture, app and action"))
        XCTAssertThrowsError(try RuleValidator.parse(output))
        let calls = await provider.requests(); XCTAssertEqual(calls.count, 0)
    }
    func testCustomLocalRequiresLoadAndCanUnload() async throws {
        let backend = LocalBackendFixture(), provider = CustomLocalModelProvider(backend: backend)
        let before = await provider.readiness(); XCTAssertFalse(before.canGenerate)
        try await provider.load(python: "/test/python", model: "/test/model")
        let after = await provider.readiness(); XCTAssertTrue(after.canGenerate)
        _ = try await provider.generate(RuleModelRequest(command: "Swipe three fingers left in Chrome to switch to previous tab", localAppContext: "Private app list"))
        let context = await backend.context(); XCTAssertEqual(context, "Private app list")
        await provider.unload()
        let end = await provider.readiness(); XCTAssertFalse(end.canGenerate)
    }
    func testFailedLocalLoadStaysUnavailable() async throws {
        let provider = CustomLocalModelProvider(backend: LocalBackendFixture(fail: true))
        do { try await provider.load(python: "/test/python", model: "/test/model"); XCTFail("Expected load failure") } catch {}
        let status = await provider.readiness(); XCTAssertFalse(status.canGenerate)
    }
    func testAPIAuditRejectsDuplicateAndEscapedDuplicateFields() throws {
        for json in ["{\"version\":1,\"version\":2}", "{\"version\":1,\"\\u0076ersion\":2}", "{\"rule\":{\"app\":\"*\",\"app\":\"com.google.Chrome\"}}", "{bad"] {
            XCTAssertThrowsError(try ModelJSONAudit.validate(Data(json.utf8)))
        }
        XCTAssertNoThrow(try ModelJSONAudit.validate(Data("{\"name\":\"Previous tab\",\"gesture\":{\"fingers\":3}}".utf8)))
    }
}
@MainActor final class ModelSettingsTests: XCTestCase {
    func testDefaultAppleSelectionDoesNotReadAPIKeys() async throws {
        let suite = "org.nicetouch.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = SettingsSecretFixture(), controller = ModelProviderController(defaults: defaults, secrets: secrets)
        await controller.refresh()
        XCTAssertEqual(controller.selection, .appleIntelligence); XCTAssertEqual(secrets.readCount(), 0)
    }
    func testAPIKeyGoesToSecretStoreAndNotPreferences() async throws {
        let suite = "org.nicetouch.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = SettingsSecretFixture(), controller = ModelProviderController(defaults: defaults, secrets: secrets)
        controller.selection = .api; controller.apiBaseURL = "https://api.example.com/v1"; controller.apiModel = "chosen-model"
        controller.apiKeyInput = "test-private-key"; await controller.saveAPIKey()
        XCTAssertEqual(controller.apiKeyInput, "")
        XCTAssertEqual(try secrets.secret(account: controller.apiConfiguration.credentialAccount()), "test-private-key")
        let domain = defaults.persistentDomain(forName: suite) ?? [:]
        // UserDefaults stores APIConfiguration as Data; inspect the decoded JSON too.
        let config = try XCTUnwrap(defaults.data(forKey: "NiceTouch.apiConfiguration"))
        XCTAssertFalse(String(decoding: config, as: UTF8.self).contains("test-private-key"))
        XCTAssertFalse(domain.keys.contains(where: { $0.lowercased().contains("apikey") }))
        XCTAssertTrue(controller.privacyLabel.contains("api.example.com")); XCTAssertFalse(controller.privacyLabel.contains("on this Mac"))
    }
    func testChangingEndpointDoesNotReuseAnotherProvidersKey() async throws {
        let suite = "org.nicetouch.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = SettingsSecretFixture(), controller = ModelProviderController(defaults: defaults, secrets: secrets)
        controller.selection = .api; controller.apiBaseURL = "https://first.example.com/v1"; controller.apiModel = "chosen-model"
        controller.apiKeyInput = "first-endpoint-key"; await controller.saveAPIKey()
        controller.apiBaseURL = "https://second.example.com/v1"; await controller.refresh()
        XCTAssertFalse(controller.hasSavedAPIKey); XCTAssertFalse(controller.status.canGenerate)
        XCTAssertNil(try secrets.secret(account: controller.apiConfiguration.credentialAccount()))
    }
}
