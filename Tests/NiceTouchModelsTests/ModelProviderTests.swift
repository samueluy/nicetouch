import XCTest
import NiceTouchCore
@testable import NiceTouchModels

private final class MemorySecrets: APISecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func secret(account: String) throws -> String? { lock.lock(); defer { lock.unlock() }; return values[account] }
    func setSecret(_ value: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = value }
    func deleteSecret(account: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account) }
}
private actor StubHTTP: RuleHTTPTransport {
    let data: Data
    let status: Int
    var requests: [URLRequest] = []
    init(data: Data, status: Int = 200) { self.data = data; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
    func count() -> Int { requests.count }
}
private actor SpyProvider: RuleModelProvider {
    let status: ModelReadiness
    let label: String
    var calls = 0
    init(_ label: String, status: ModelReadiness = .ready) { self.label = label; self.status = status }
    func readiness() async -> ModelReadiness { status }
    func generate(_ request: RuleModelRequest) async throws -> String { calls += 1; return label }
    func count() -> Int { calls }
}
final class ModelProviderTests: XCTestCase {
    let config = APIConfiguration(baseURL: "https://api.example.com/v1", model: "user-selected-model")
    func request() throws -> RuleModelRequest {
        try RuleModelRequest(command: "When I swipe three fingers left in Chrome, switch to the previous tab.", localAppContext: "PrivateFinance com.private.Finance", knownApps: ["com.private.Finance": "PrivateFinance"])
    }
    func providerReply(result: [String: Any], finish: String = "stop") throws -> Data {
        let content = String(decoding: try JSONSerialization.data(withJSONObject: ["result": result]), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": finish, "message": ["content": content]]]])
    }
    var definition: [String: Any] {
        ["version": 1, "name": "Previous tab", "app": "com.google.Chrome", "gesture": ["kind": "swipe", "fingers": 3, "direction": "left", "zone": "anywhere"], "action": "previousTab"]
    }
    func testAppleIntelligenceIsPreferenceDefaultAndExplicitChoicesPersist() throws {
        let name = "org.nicetouch.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(ModelProviderPreferences.selection(in: defaults), .appleIntelligence)
        ModelProviderPreferences.save(.api, in: defaults)
        XCTAssertEqual(ModelProviderPreferences.selection(in: defaults), .api)
        defaults.set("unknown-provider", forKey: "NiceTouch.modelProvider")
        XCTAssertEqual(ModelProviderPreferences.selection(in: defaults), .appleIntelligence)
    }
    func testRegistryUsesAppleByDefault() async throws {
        let apple = SpyProvider("apple"), local = SpyProvider("local"), api = SpyProvider("api")
        let registry = ModelProviderRegistry(apple: apple, customLocal: local, api: api)
        let result = try await registry.generate(request())
        XCTAssertEqual(result, "apple")
        let counts = await [apple.count(), local.count(), api.count()]
        XCTAssertEqual(counts, [1, 0, 0])
    }
    func testUnavailableAppleDoesNotFallBackToNetwork() async throws {
        let apple = SpyProvider("apple", status: .unavailable("Apple Intelligence is off")), api = SpyProvider("api")
        let registry = ModelProviderRegistry(apple: apple, api: api)
        do { _ = try await registry.generate(request()); XCTFail("Expected availability error") }
        catch { XCTAssertEqual(error as? RuleModelError, .unavailable("Apple Intelligence is off")) }
        let calls = await api.count(); XCTAssertEqual(calls, 0)
    }
    func testAPIRequiresExplicitSelection() async throws {
        let apple = SpyProvider("apple"), api = SpyProvider("api")
        let registry = ModelProviderRegistry(apple: apple, api: api)
        let result = try await registry.generate(request(), using: .api)
        XCTAssertEqual(result, "api")
        let calls = await apple.count(); XCTAssertEqual(calls, 0)
    }
    func testCustomLocalSelectionUsesItsProvider() async throws {
        let local = SpyProvider("local"), api = SpyProvider("api")
        let registry = ModelProviderRegistry(customLocal: local, api: api)
        let result = try await registry.generate(request(), using: .customLocal)
        XCTAssertEqual(result, "local")
        let calls = await api.count(); XCTAssertEqual(calls, 0)
    }
    func testRequestHasSizeAndEmptyInputLimits() {
        XCTAssertThrowsError(try RuleModelRequest(command: "  "))
        XCTAssertThrowsError(try RuleModelRequest(command: String(repeating: "x", count: 8193)))
    }
    func testRemoteRequestExcludesInstalledAppsAndKeepsKeyOutOfBody() throws {
        let call = try APIRequestBuilder.make(configuration: config, secret: "test-key-not-a-real-secret", request: request())
        XCTAssertEqual(call.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(call.value(forHTTPHeaderField: "Authorization"), "Bearer test-key-not-a-real-secret")
        let body = String(decoding: try XCTUnwrap(call.httpBody), as: UTF8.self)
        XCTAssertFalse(body.contains("PrivateFinance")); XCTAssertFalse(body.contains("com.private.Finance"))
        XCTAssertFalse(body.contains("test-key-not-a-real-secret"))
        let local = try request().prompt(includeLocalContext: true)
        XCTAssertTrue(local.contains("PrivateFinance"))
    }
    func testAPISchemaUsesSupportedStrictObjectShape() throws {
        let schema = APIRuleSchema.envelope
        XCTAssertEqual(schema["type"] as? String, "object"); XCTAssertNil(schema["anyOf"])
        func walk(_ value: Any) throws {
            if let object = value as? [String: Any] {
                for banned in ["allOf", "if", "then", "else"] { XCTAssertNil(object[banned]) }
                if object["type"] as? String == "object" {
                    XCTAssertEqual(object["additionalProperties"] as? Bool, false)
                    let props = try XCTUnwrap(object["properties"] as? [String: Any])
                    XCTAssertEqual(Set(try XCTUnwrap(object["required"] as? [String])), Set(props.keys))
                }
                for child in object.values { try walk(child) }
            } else if let array = value as? [Any] { for child in array { try walk(child) } }
        }
        try walk(schema)
    }
    func testAPIRequestEnablesStrictSchemaOutput() throws {
        let request = try APIRequestBuilder.make(configuration: config, secret: "test-key", request: self.request())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let format = try XCTUnwrap(object["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let wrapper = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(wrapper["strict"] as? Bool, true)
    }
    func testEndpointRejectsRemoteHTTPEmbeddedCredentialsAndQueryStrings() {
        for url in ["http://api.example.com/v1", "https://user:password@api.example.com/v1", "https://api.example.com/v1?key=private", "https://api.example.com/v1#private", "file:///tmp/model"] {
            XCTAssertThrowsError(try APIConfiguration(baseURL: url, model: "model").validate(), url)
        }
    }
    func testLoopbackAllowsHTTPAndNormalizesEndpoint() throws {
        for host in ["localhost", "127.0.0.1", "[::1]"] {
            let config = APIConfiguration(baseURL: "http://\(host):1234/v1/", model: "local")
            XCTAssertTrue(try config.endpoint().absoluteString.hasSuffix("/v1/chat/completions"))
        }
        let full = APIConfiguration(baseURL: "https://api.example.com/v1/chat/completions", model: "model")
        XCTAssertEqual(try full.endpoint().absoluteString, full.baseURL)
    }
    func testMissingModelOrKeyAndHeaderInjectionAreRejectedBeforeNetworking() throws {
        XCTAssertThrowsError(try APIConfiguration(baseURL: config.baseURL, model: "").validate())
        XCTAssertThrowsError(try APIRequestBuilder.make(configuration: config, secret: nil, request: request()))
        XCTAssertThrowsError(try APIRequestBuilder.make(configuration: config, secret: "key\r\nX-Evil: yes", request: request()))
    }
    func testKeylessOptInDoesNotSendAuthorizationEvenIfKeyExists() throws {
        var config = config; config.requiresAPIKey = false
        let call = try APIRequestBuilder.make(configuration: config, secret: "unused-key", request: request())
        XCTAssertNil(call.value(forHTTPHeaderField: "Authorization"))
    }
    func testAPIAdapterReturnsDefinitionForCoreValidation() async throws {
        let secrets = MemorySecrets(); try secrets.setSecret("test-key", account: config.credentialAccount())
        let transport = StubHTTP(data: try providerReply(result: ["kind": "rule", "definition": definition]))
        let provider = APIRuleProvider(configuration: config, secrets: secrets, transport: transport)
        let text = try await provider.generate(request())
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(parsed["action"] as? String, "previousTab"); XCTAssertEqual(parsed["app"] as? String, "com.google.Chrome")
        let calls = await transport.count(); XCTAssertEqual(calls, 1)
    }
    func testAPIClarificationDoesNotProduceRule() async throws {
        let secrets = MemorySecrets(); try secrets.setSecret("test-key", account: config.credentialAccount())
        let transport = StubHTTP(data: try providerReply(result: ["kind": "clarification", "question": "Which app should use the gesture?"]))
        let text = try await APIRuleProvider(configuration: config, secrets: secrets, transport: transport).generate(request())
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String])
        XCTAssertEqual(parsed, ["error": "Which app should use the gesture?"])
    }
    func testAPIRedirectsFailWithoutASecondRequest() async throws {
        let secrets = MemorySecrets(); try secrets.setSecret("test-key", account: config.credentialAccount())
        let transport = StubHTTP(data: Data(), status: 302)
        do { _ = try await APIRuleProvider(configuration: config, secrets: secrets, transport: transport).generate(request()); XCTFail("Expected redirect error") }
        catch { XCTAssertEqual(error as? RuleModelError, .redirected) }
        let calls = await transport.count(); XCTAssertEqual(calls, 1)
    }
    func testTransportRedirectDelegateDoesNotForwardCredentials() throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://api.example.com")!)
        let response = HTTPURLResponse(url: task.originalRequest!.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var next: URLRequest? = URLRequest(url: URL(string: "https://unexpected.example.com")!)
        DenyAPIRedirects().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: next!) { next = $0 }
        XCTAssertNil(next)
    }
    func testAuthenticationErrorDoesNotExposeProviderResponseBody() async throws {
        let secrets = MemorySecrets(); try secrets.setSecret("test-key", account: config.credentialAccount())
        let transport = StubHTTP(data: Data("private echoed API key".utf8), status: 401)
        do { _ = try await APIRuleProvider(configuration: config, secrets: secrets, transport: transport).generate(request()); XCTFail("Expected authentication error") }
        catch { XCTAssertEqual(error as? RuleModelError, .http(401)); XCTAssertFalse(error.localizedDescription.contains("private echoed")) }
    }
    func testAPIRefusalAndTruncatedRepliesAreRejected() async throws {
        let secrets = MemorySecrets(); try secrets.setSecret("test-key", account: config.credentialAccount())
        let refusal = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["refusal": "declined"]]]])
        for (data, expected) in [(refusal, RuleModelError.refused), (try providerReply(result: ["kind": "rule", "definition": definition], finish: "length"), .malformedReply)] {
            let transport = StubHTTP(data: data)
            do { _ = try await APIRuleProvider(configuration: config, secrets: secrets, transport: transport).generate(request()); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? RuleModelError, expected) }
        }
    }
    func testOversizedAPIReplyIsRejected() async throws {
        let secrets = MemorySecrets(); try secrets.setSecret("test-key", account: config.credentialAccount())
        let transport = StubHTTP(data: Data(repeating: 32, count: 262_145))
        do { _ = try await APIRuleProvider(configuration: config, secrets: secrets, transport: transport).generate(request()); XCTFail("Expected size error") }
        catch { XCTAssertEqual(error as? RuleModelError, .replyTooLarge) }
    }
    func testAPIDrawingLaunchSurvivesAuthoringValidation() async throws {
        let secrets = MemorySecrets(); try secrets.setSecret("test-key", account: config.credentialAccount())
        let rule = RuleDefinition(name: "Open Codex", app: "*", gesture: Gesture(kind: .drawC, fingers: 1, direction: .none), action: .openCodex)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rule.json.utf8)) as? [String: Any])
        let transport = StubHTTP(data: try providerReply(result: ["kind": "rule", "definition": object]))
        let provider = APIRuleProvider(configuration: config, secrets: secrets, transport: transport)
        let output = try await RuleAuthoringPipeline.generate(RuleModelRequest(command: "Open Codex when I draw a C"), provider: provider) { _ = try RuleValidator.parse($0) }
        XCTAssertEqual(try RuleValidator.parse(output), rule)
    }
    func testAppleGuidedDrawingMapsToOneFingerAndWhitelistedLaunch() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Foundation Models requires macOS 26") }
        let drawing = AppleRule(name: "Open ChatGPT", app: "*", gesture: .drawC(zone: .anywhere), action: .openChatGPT)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(drawing.json().utf8)) as? [String: Any])
        XCTAssertEqual(object["action"] as? String, "openChatGPT")
        let gesture = try XCTUnwrap(object["gesture"] as? [String: Any])
        XCTAssertEqual(gesture["kind"] as? String, "drawC")
        XCTAssertEqual(gesture["fingers"] as? Int, 1)
        XCTAssertEqual(gesture["direction"] as? String, "none")
    }
    func testAppleGuidedTypesMapTapAndSwipeToExistingRuleJSON() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Foundation Models requires macOS 26") }
        let tap = AppleRule(name: "Copy", app: "*", gesture: .tap(fingers: .four, zone: .top), action: .copy)
        let parsedTap = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(tap.json().utf8)) as? [String: Any])
        let gesture = try XCTUnwrap(parsedTap["gesture"] as? [String: Any])
        XCTAssertEqual(gesture["fingers"] as? Int, 4); XCTAssertEqual(gesture["direction"] as? String, "none")
        let swipe = AppleRule(name: "Previous tab", app: "com.google.Chrome", gesture: .swipe(fingers: .three, direction: .left, zone: .anywhere), action: .previousTab)
        let parsedSwipe = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(swipe.json().utf8)) as? [String: Any])
        XCTAssertEqual((parsedSwipe["gesture"] as? [String: Any])?["direction"] as? String, "left")
        XCTAssertEqual(parsedSwipe["version"] as? Int, 1)
    }
}
