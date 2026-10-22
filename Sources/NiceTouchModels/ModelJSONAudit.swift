import Foundation

/// Reject duplicate keys before JSONSerialization can collapse them.
enum ModelJSONAudit {
    static func validate(_ data: Data) throws {
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { throw RuleModelError.malformedReply }
        var audit = Reader(bytes: Array(data))
        try audit.value(depth: 0)
    }
    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        mutating func whitespace() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        mutating func string() throws -> String {
            let start = index; index += 1
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if byte == 92 { index += 1 }
                else if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
            }
            throw RuleModelError.malformedReply
        }
        mutating func value(depth: Int) throws {
            guard depth <= 64 else { throw RuleModelError.malformedReply }
            whitespace(); guard index < bytes.count else { throw RuleModelError.malformedReply }
            switch bytes[index] {
            case 123:
                index += 1; whitespace(); var keys = Set<String>()
                while index < bytes.count && bytes[index] != 125 {
                    guard keys.insert(try string()).inserted else { throw RuleModelError.malformedReply }
                    whitespace(); index += 1
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
}
