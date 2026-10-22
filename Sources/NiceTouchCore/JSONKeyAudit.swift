import Foundation

/// JSONSerialization validates syntax but silently collapses duplicate keys.
/// Audit the original bytes so ambiguous model or persisted JSON is rejected.
struct JSONKeyAudit {
    private let bytes: [UInt8]
    private var index = 0
    static func validate(_ data: Data) throws {
        var audit = JSONKeyAudit(bytes: Array(data))
        try audit.value(depth: 0)
    }
    private mutating func whitespace() {
        while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    private mutating func string() throws -> String {
        let start = index
        index += 1
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 92 { index += 1 }
            else if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
        }
        throw RuleError("Unterminated JSON string.")
    }
    private mutating func value(depth: Int) throws {
        guard depth <= 64 else { throw RuleError("JSON nesting exceeds 64 levels.") }
        whitespace()
        guard index < bytes.count else { throw RuleError("Incomplete JSON.") }
        switch bytes[index] {
        case 123:
            index += 1; whitespace()
            var seen = Set<String>()
            while index < bytes.count && bytes[index] != 125 {
                let key = try string()
                guard seen.insert(key).inserted else { throw RuleError("Duplicate JSON field: \(key). Each field must appear exactly once.") }
                whitespace(); index += 1 // colon; syntax already checked by JSONSerialization
                try value(depth: depth + 1); whitespace()
                if index < bytes.count && bytes[index] == 44 { index += 1; whitespace() }
            }
            index += 1
        case 91:
            index += 1; whitespace()
            while index < bytes.count && bytes[index] != 93 {
                try value(depth: depth + 1); whitespace()
                if index < bytes.count && bytes[index] == 44 { index += 1; whitespace() }
            }
            index += 1
        case 34: _ = try string()
        default:
            while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
        }
    }
}
