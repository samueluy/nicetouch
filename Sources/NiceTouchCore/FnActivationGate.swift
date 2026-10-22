import Foundation

/// One gate per physical contact sequence and per trackpad device.
/// A denied/cancelled sequence cannot become eligible until every finger lifts.
public struct FnActivationGate {
    private var active = false
    private var admitted = false
    private var initialRequirement = true
    public init() {}
    public mutating func reset() { self = FnActivationGate() }
    public mutating func cancel() { if active { admitted = false } }
    public mutating func allowsFrame(contactCount: Int, fnPressed: Bool, requiresFn: Bool = true) -> Bool {
        guard contactCount >= 0 else { reset(); return false }
        if !active {
            guard contactCount > 0 else { return false }
            active = true
            initialRequirement = requiresFn
            admitted = !requiresFn || fnPressed
        } else if requiresFn != initialRequirement {
            admitted = false
        }
        if requiresFn && !fnPressed { admitted = false }
        let allowed = admitted
        if contactCount == 0 { reset() }
        return allowed
    }
}
