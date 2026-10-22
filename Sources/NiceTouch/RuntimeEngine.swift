import AppKit
import ApplicationServices
import NiceTouchCore
import TrackpadBridge

private let captureFence = CaptureSessionFence()

private func receiveFrame(_ device: UInt, _ xs: UnsafePointer<Float>?, _ ys: UnsafePointer<Float>?, _ count: Int32, _ time: Double) {
    guard let session = captureFence.snapshot(), count >= 0, count <= 16, let xs, let ys else { return }
    let contacts = (0..<Int(count)).map { Contact(x: Double(xs[$0]), y: Double(ys[$0])) }
    let fnPressed = CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn)
    DispatchQueue.main.async {
        guard captureFence.accepts(session) else { return }
        RuntimeEngine.current?.feed(device: device, contacts: contacts, time: time, fnPressed: fnPressed)
    }
}

/// Testable boundaries around OS capture, permissions and action delivery.
/// Production uses the real services; tests never register capture or post input.
@MainActor struct RuntimeServices {
    var hasAccessibility: () -> Bool = { AXIsProcessTrusted() }
    var fnHeld: () -> Bool = { CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn) }
    var activeApp: () -> String = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "" }
    var startCapture: (NTFrameCallback) -> Bool = { NTStart($0) }
    var stopCapture: () -> Void = { NTStop() }
    var actionHandler: ((RuleAction) -> Bool)?
    var installObservers = true
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
    private let services: RuntimeServices
    private var captureSession: UUID?
    init(services: RuntimeServices? = nil) {
        self.services = services ?? RuntimeServices()
        guard self.services.installObservers else { return }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.cancelForAppSwitch()
            }
        }
    }
    func start() throws {
        guard !running else { return }
        guard services.hasAccessibility() else { throw RuleError("Grant NiceTouch Accessibility access in System Settings, then start the engine again.") }
        if let previous = RuntimeEngine.current, previous !== self { previous.stop() }
        RuntimeEngine.current = self
        let session = captureFence.begin(); captureSession = session
        guard services.startCapture(receiveFrame) else {
            captureFence.end(session); captureSession = nil; RuntimeEngine.current = nil
            throw RuleError("No supported built-in trackpad was found, or the experimental macOS API is unavailable.")
        }
        running = true
        guard services.installObservers else { return }
        globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if !event.modifierFlags.contains(.function) {
                Task { @MainActor in if self?.captureSession == session, self?.requireFn == true { self?.cancelFnSequences() } }
            }
        }
        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if !event.modifierFlags.contains(.function) {
                Task { @MainActor in if self?.captureSession == session, self?.requireFn == true { self?.cancelFnSequences() } }
            }
            return event
        }
    }
    func stop() {
        let hadCapture = captureSession != nil
        running = false
        if let session = captureSession { captureFence.end(session) }
        captureSession = nil
        if RuntimeEngine.current === self { RuntimeEngine.current = nil }
        if hadCapture { services.stopCapture() }
        if let monitor = globalModifierMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localModifierMonitor { NSEvent.removeMonitor(monitor) }
        globalModifierMonitor = nil; localModifierMonitor = nil
        fnGates.removeAll(); recognizers.removeAll(); startApps.removeAll()
        lastExecution = -Double.infinity
    }
    func cancelForAppSwitch() {
        for device in Array(startApps.keys) { startApps[device] = "" }
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
        let app = services.activeApp()
        if startApps[device] == nil && !contacts.isEmpty { startApps[device] = app }
        if startApps[device] != nil && startApps[device] != app { startApps[device] = "" }
        var recognizer = recognizers[device] ?? GestureRecognizer()
        let event = recognizer.feed(contacts, time: time)
        recognizers[device] = recognizer
        defer { if contacts.isEmpty { startApps.removeValue(forKey: device) } }
        guard let event, startApps[device] == app, time - lastExecution > 0.35,
              let rule = RuleMatcher.match(event, app: app, rules: rules) else { return }
        guard services.hasAccessibility() else { stop(); onEvent?("Accessibility access was revoked. Engine stopped."); return }
        if requireFn && !services.fnHeld() {
            cancelFnSequences(); return
        }
        guard execute(rule.definition.action) else { return }
        lastExecution = time
        onEvent?("\(rule.definition.action.label) · \(rule.definition.appLabel)")
    }
    private func execute(_ action: RuleAction) -> Bool {
        if let handler = services.actionHandler { return handler(action) }
        if let bundleID = action.launchBundleIdentifier {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                onEvent?("\(action.label.replacingOccurrences(of: "Open ", with: "")) is not installed on this Mac."); return false
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                if let error { Task { @MainActor in self?.onEvent?("Could not open app: " + error.localizedDescription) } }
            }
            return true
        }
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
        case .openChatGPT, .openCodex: return false
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { onEvent?("Could not create keyboard events."); return false }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return true
    }
}
