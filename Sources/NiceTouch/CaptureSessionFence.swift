import Foundation

/// Native callbacks can arrive off-main and remain queued across Pause/Start.
/// An old delivery must never reach a newly started engine.
final class CaptureSessionFence: @unchecked Sendable {
    private let lock = NSLock()
    private var active: UUID?
    func begin() -> UUID {
        lock.lock(); defer { lock.unlock() }
        let token = UUID(); active = token; return token
    }
    func snapshot() -> UUID? {
        lock.lock(); defer { lock.unlock() }
        return active
    }
    func accepts(_ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active == token
    }
    func end(_ token: UUID) {
        lock.lock(); defer { lock.unlock() }
        if active == token { active = nil }
    }
}
