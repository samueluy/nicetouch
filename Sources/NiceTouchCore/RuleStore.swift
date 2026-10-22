import Foundation

public struct RuleStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [SavedRule] {
        guard FileManager.default.fileExists(atPath: url.path) else { return Samples.rules }
        let data = try Data(contentsOf: url)
        guard data.count <= 8_000_000 else { throw RuleError("Rule file exceeds 8 MB.") }
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], entries.count <= 500 else {
            throw RuleError("Expected an array with at most 500 saved rules.")
        }
        try JSONKeyAudit.validate(data)
        for entry in entries {
            guard Set(entry.keys) == ["id", "enabled", "definition"], let definition = entry["definition"] as? [String: Any] else {
                throw RuleError("Saved rules must contain only id, enabled, and definition.")
            }
            let text = String(decoding: try JSONSerialization.data(withJSONObject: definition), as: UTF8.self)
            _ = try RuleValidator.parse(text)
        }
        let rules = try JSONDecoder().decode([SavedRule].self, from: data)
        try RuleValidator.validateCollection(rules)
        return rules
    }
    public func save(_ rules: [SavedRule]) throws {
        try RuleValidator.validateCollection(rules)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rules).write(to: url, options: .atomic)
    }
}
