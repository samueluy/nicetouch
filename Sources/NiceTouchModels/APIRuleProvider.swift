import Foundation

public protocol RuleHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
final class DenyAPIRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public actor URLSessionRuleTransport: RuleHTTPTransport {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config, delegate: DenyAPIRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { bytes.task.cancel(); throw RuleModelError.malformedReply }
        guard (200..<300).contains(response.statusCode) else { bytes.task.cancel(); return (Data(), response) }
        var data = Data()
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 262_144 else { throw RuleModelError.replyTooLarge }
                data.append(byte)
            }
        } catch { bytes.task.cancel(); throw error }
        return (data, response)
    }
}
public actor APIRuleProvider: RuleModelProvider {
    private let configuration: APIConfiguration
    private let secrets: any APISecretStore
    private let transport: (any RuleHTTPTransport)?
    public init(configuration: APIConfiguration, secrets: any APISecretStore = KeychainAPISecretStore(), transport: (any RuleHTTPTransport)? = nil) {
        self.configuration = configuration; self.secrets = secrets; self.transport = transport
    }
    public func readiness() async -> ModelReadiness {
        do {
            try configuration.validate()
            if configuration.requiresAPIKey {
                guard let key = try secrets.secret(account: configuration.credentialAccount()), !key.isEmpty else {
                    return .needsConfiguration("Save an API key for this endpoint in Keychain.")
                }
            }
            return .ready
        } catch { return .needsConfiguration(error.localizedDescription) }
    }
    public func generate(_ request: RuleModelRequest) async throws -> String {
        let key = configuration.requiresAPIKey ? try secrets.secret(account: configuration.credentialAccount()) : nil
        let call = try APIRequestBuilder.make(configuration: configuration, secret: key, request: request)
        let transport = self.transport ?? URLSessionRuleTransport()
        let (data, response) = try await transport.send(call)
        if (300..<400).contains(response.statusCode) { throw RuleModelError.redirected }
        guard (200..<300).contains(response.statusCode) else { throw RuleModelError.http(response.statusCode) }
        guard data.count <= 262_144 else { throw RuleModelError.replyTooLarge }
        try ModelJSONAudit.validate(data)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]], let choice = choices.first,
              let message = choice["message"] as? [String: Any] else { throw RuleModelError.malformedReply }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw RuleModelError.refused }
        guard choice["finish_reason"] as? String == "stop", let content = message["content"] as? String,
              content.utf8.count <= 16_384, let encoded = content.data(using: .utf8),
              (try? ModelJSONAudit.validate(encoded)) != nil,
              let envelope = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              Set(envelope.keys) == ["result"], let result = envelope["result"] as? [String: Any] else { throw RuleModelError.malformedReply }
        if result["kind"] as? String == "rule", Set(result.keys) == ["kind", "definition"], let definition = result["definition"] as? [String: Any] {
            // Keep semantic validation and conflict checks in NiceTouchCore.
            return String(decoding: try JSONSerialization.data(withJSONObject: definition, options: .sortedKeys), as: UTF8.self)
        }
        if result["kind"] as? String == "clarification", Set(result.keys) == ["kind", "question"], let question = result["question"] as? String,
           !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(decoding: try JSONSerialization.data(withJSONObject: ["error": question]), as: UTF8.self)
        }
        throw RuleModelError.malformedReply
    }
}
