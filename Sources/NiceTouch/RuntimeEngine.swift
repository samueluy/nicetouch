import AppKit
import ApplicationServices
import NiceTouchCore
import TrackpadBridge

private func receiveFrame(_ device: UInt, _ xs: UnsafePointer<Float>?, _ ys: UnsafePointer<Float>?, _ count: Int32, _ time: Double) {
    guard count >= 0, count <= 16, let xs, let ys else { return }
    let contacts = (0..<Int(count)).map { Contact(x: Double(xs[$0]), y: Double(ys[$0])) }
    let fnPressed = CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn)
    DispatchQueue.main.async { RuntimeEngine.current?.feed(device: device, contacts: contacts, time: time, fnPressed: fnPressed) }
}

@MainActor final class RuntimeEngine {
    static weak var current: RuntimeEngine?
    var rules: [SavedRule] = []
    var onEvent: ((String) -> Void)?
    private(set) var running = false
    var requireFn = true {
        didSet { if oldValue != requireFn { cancelFnSequences() } }
    }
    private var fnGates: [UInt: FnActivationGate] = [:]
    private var globalModifierMonitor: Any?
    private var localModifierMonitor: Any?
    private var recognizers: [UInt: GestureRecognizer] = [:]
    private var startApps: [UInt: String] = [:]
    private var lastExecution = -Double.infinity
    private var appObserver: NSObjectProtocol?
    init() {
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                for device in self.startApps.keys { self.startApps[device] = "" }
            }
        }
    }
    func start() throws {
        guard !running else { return }
        guard AXIsProcessTrusted() else { throw RuleError("Grant NiceTouch Accessibility access in System Settings, then start the engine again.") }
        RuntimeEngine.current = self
        guard NTStart(receiveFrame) else { throw RuleError("No supported built-in trackpad was found, or the experimental macOS API is unavailable.") }
        running = true
        globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if !event.modifierFlags.contains(.function) {
                Task { @MainActor in if self?.requireFn == true { self?.cancelFnSequences() } }
            }
        }
        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if !event.modifierFlags.contains(.function) {
                Task { @MainActor in if self?.requireFn == true { self?.cancelFnSequences() } }
            }
            return event
        }
    }
    func stop() {
        running = false; NTStop()
        if let monitor = globalModifierMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localModifierMonitor { NSEvent.removeMonitor(monitor) }
        globalModifierMonitor = nil; localModifierMonitor = nil
        fnGates.removeAll(); recognizers.removeAll(); startApps.removeAll()
        lastExecution = -Double.infinity
    }
    private func cancelFnSequences() {
        for device in Array(fnGates.keys) { fnGates[device]?.cancel() }
        recognizers.removeAll(); startApps.removeAll()
    }
    func feed(device: UInt, contacts: [Contact], time: Double, fnPressed: Bool) {
        guard running else { return }
        var gate = fnGates[device] ?? FnActivationGate()
        let allowed = gate.allowsFrame(contactCount: contacts.count, fnPressed: fnPressed, requiresFn: requireFn)
        if contacts.isEmpty { fnGates.removeValue(forKey: device) } else { fnGates[device] = gate }
        guard allowed else {
            recognizers.removeValue(forKey: device); startApps.removeValue(forKey: device)
            return
        }
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if startApps[device] == nil && !contacts.isEmpty { startApps[device] = app }
        if startApps[device] != nil && startApps[device] != app { startApps[device] = "" }
        var recognizer = recognizers[device] ?? GestureRecognizer()
        let event = recognizer.feed(contacts, time: time)
        recognizers[device] = recognizer
        defer { if contacts.isEmpty { startApps.removeValue(forKey: device) } }
        guard let event, startApps[device] == app, time - lastExecution > 0.35,
              let rule = RuleMatcher.match(event, app: app, rules: rules) else { return }
        guard AXIsProcessTrusted() else { stop(); onEvent?("Accessibility access was revoked. Engine stopped."); return }
        if requireFn && !CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn) {
            cancelFnSequences(); return
        }
        guard post(rule.definition.action) else { onEvent?("Could not create keyboard events."); return }
        lastExecution = time
        onEvent?("\(rule.definition.action.label) · \(rule.definition.appLabel)")
    }
    private func post(_ action: RuleAction) -> Bool {
        let key: CGKeyCode
        let flags: CGEventFlags
        switch action {
        case .previousTab: key = 48; flags = [.maskControl, .maskShift]
        case .nextTab: key = 48; flags = .maskControl
        case .closeTab: key = 13; flags = .maskCommand
        case .reopenTab: key = 17; flags = [.maskCommand, .maskShift]
        case .copy: key = 8; flags = .maskCommand
        case .paste: key = 9; flags = .maskCommand
        case .undo: key = 6; flags = .maskCommand
        case .redo: key = 6; flags = [.maskCommand, .maskShift]
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return true
    }
}
