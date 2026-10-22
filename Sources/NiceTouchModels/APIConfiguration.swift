import Foundation

public struct APIConfiguration: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var requiresAPIKey: Bool
    public init(baseURL: String = "", model: String = "", requiresAPIKey: Bool = true) {
        self.baseURL = baseURL; self.model = model; self.requiresAPIKey = requiresAPIKey
    }
    public func endpoint() throws -> URL {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil else {
            throw RuleModelError.invalidConfiguration("Enter an API base URL without embedded credentials, query parameters or fragments.")
        }
        let hostName = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        let isLoopback = ["localhost", "127.0.0.1", "::1"].contains(hostName)
        guard components.scheme == "https" || (components.scheme == "http" && isLoopback) else {
            throw RuleModelError.invalidConfiguration("Use HTTPS for remote APIs. HTTP is allowed for a loopback server on this Mac.")
        }
        if let port = components.port, !(1...65535).contains(port) { throw RuleModelError.invalidConfiguration("Enter a valid API port.") }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        components.path = path
        guard let url = components.url else { throw RuleModelError.invalidConfiguration("Enter a valid API URL.") }
        return url
    }
    public func validate() throws {
        _ = try endpoint()
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value == model, model.utf8.count <= 200,
              !model.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw RuleModelError.invalidConfiguration("Enter the provider's exact model ID.")
        }
    }
    public func credentialAccount() throws -> String { try endpoint().absoluteString }
    public var disclosure: String {
        guard let url = try? endpoint(), let host = url.host else { return "Choose an API endpoint before sending a command." }
        return "Send the command and rule instructions to \(host). NiceTouch does not send saved rules, gesture activity or the running-app list. Provider fees and data policies apply."
    }
}
public protocol APISecretStore: Sendable {
    func secret(account: String) throws -> String?
    func setSecret(_ value: String, account: String) throws
    func deleteSecret(account: String) throws
}
public enum APIRuleSchema {
    public static var envelope: [String: Any] {
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "additionalProperties": false, "required": properties.keys.sorted(), "properties": properties]
        }
        func choice(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }
        let gesture = object([
            "kind": choice(["swipe", "tap"]), "fingers": ["type": "integer", "enum": [3, 4]],
            "direction": choice(["left", "right", "up", "down", "none"]),
            "zone": choice(["anywhere", "left", "right", "top", "bottom"])
        ])
        let definition = object([
            "version": ["type": "integer", "enum": [1]], "name": ["type": "string"], "app": ["type": "string"], "gesture": gesture,
            "action": choice(["previousTab", "nextTab", "closeTab", "reopenTab", "copy", "paste", "undo", "redo"])
        ])
        let ready = object(["kind": choice(["rule"]), "definition": definition])
        let question = object(["kind": choice(["clarification"]), "question": ["type": "string"]])
        // API strict schemas require an object root; anyOf is nested in result.
        return object(["result": ["anyOf": [ready, question]]])
    }
}
public enum APIRequestBuilder {
    public static func make(configuration: APIConfiguration, secret: String?, request: RuleModelRequest) throws -> URLRequest {
        try configuration.validate()
        var result = URLRequest(url: try configuration.endpoint(), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        result.httpMethod = "POST"
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if configuration.requiresAPIKey {
            guard let secret, !secret.isEmpty, secret.utf8.count <= 8192,
                  secret.unicodeScalars.allSatisfy({ (33...126).contains(Int($0.value)) }) else {
                throw RuleModelError.invalidConfiguration("Save a valid API key for this endpoint in Keychain.")
            }
            result.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": configuration.model,
            "messages": [["role": "system", "content": RuleModelInstructions.api], ["role": "user", "content": try request.prompt(includeLocalContext: false)]],
            "max_completion_tokens": 1024,
            "response_format": ["type": "json_schema", "json_schema": ["name": "nicetouch_rule", "strict": true, "schema": APIRuleSchema.envelope]]
        ]
        result.httpBody = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        return result
    }
}
