import SwiftUI
import AppKit
import NiceTouchCore
import NiceTouchModels

@MainActor final class AppState: ObservableObject {
    @Published var rules: [SavedRule] = []
    @Published var selected: UUID?
    @Published var command = ""
    @Published var rawJSON = ""
    @Published var draft: RuleDefinition?
    @Published var warning = ""
    @Published var busy = false
    @Published var requireFn = UserDefaults.standard.object(forKey: "requireFn") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(requireFn, forKey: "requireFn")
            engine.requireFn = requireFn
        }
    }
    @Published var engineRunning = false
    @Published var lastEvent = "Gestures paused"
    @Published var showModel = false
    let models: ModelProviderController
    private let engine = RuntimeEngine()
    private var loadFailed = false
    private var sleepObserver: NSObjectProtocol?
    private let store = RuleStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NiceTouch/rules.json"))
    init() {
        models = ModelProviderController(customLocal: CustomLocalModelProvider(backend: LocalModel()))
        do { rules = try store.load(); selected = rules.first?.id }
        catch { loadFailed = true; warning = "Could not load rules. Your file has been preserved. \(error.localizedDescription)" }
        engine.rules = rules
        engine.requireFn = requireFn
        engine.onEvent = { [weak self] message in self?.lastEvent = message; self?.engineRunning = self?.engine.running ?? false }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopEngine() }
        }
    }
    var conflicts: [SavedRule] { draft.map { RuleValidator.conflicts($0, with: rules) } ?? [] }
    var selectedRule: RuleDefinition? { draft ?? rules.first(where: { $0.id == selected })?.definition }
    func generate() {
        guard !busy, !models.busy, models.status.canGenerate, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; draft = nil; rawJSON = ""; warning = ""
        let request = command
        let appReferences = NSWorkspace.shared.runningApplications.compactMap { app -> (String, String)? in
            guard let id = app.bundleIdentifier, app.activationPolicy == .regular else { return nil }
            return (id, app.localizedName ?? id)
        }
        let knownApps = Dictionary(appReferences, uniquingKeysWith: { first, _ in first })
        let apps = models.selection == .api ? "" : appReferences.map { "\($0.1): \($0.0)" }.joined(separator: ", ")
        Task {
            defer { busy = false }
            do {
                let result = try await models.author(command: request, localAppContext: apps, knownApps: knownApps) { output in
                    _ = try RuleValidator.parse(output)
                }
                rawJSON = result
                if let data = result.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   Set(object.keys) == ["error"], let clarification = object["error"] as? String {
                    warning = clarification
                } else {
                    draft = try RuleValidator.parse(result)
                    warning = conflictMessage
                }
            } catch let error as InvalidRuleModelOutput {
                rawJSON = error.output
                warning = error.suggestion + " Specify the app, finger count, direction and supported action."
            } catch {
                warning = error.localizedDescription
            }
        }
    }
    private var conflictMessage: String {
        guard !conflicts.isEmpty else { return "" }
        return "This gesture is assigned to " + conflicts.map { "\($0.definition.name) → \($0.definition.action.label)" }.joined(separator: ", ") + ". Disable the existing rule or change the app, gesture or zone."
    }
    func discardPreview() { draft = nil; rawJSON = ""; warning = "" }
    func saveDraft() {
        guard let draft else { return }
        guard conflicts.isEmpty else { warning = conflictMessage; return }
        let saved = SavedRule(definition: draft)
        if persist(rules + [saved]) { selected = saved.id; self.draft = nil; rawJSON = ""; command = ""; lastEvent = "Gesture saved" }
    }
    func toggle(_ rule: SavedRule) {
        if !rule.enabled {
            let blocking = RuleValidator.conflicts(rule.definition, with: rules, excluding: rule.id)
            guard blocking.isEmpty else {
                warning = "Cannot enable \(rule.definition.name): this gesture is assigned to " + blocking.map { "\($0.definition.name) → \($0.definition.action.label)" }.joined(separator: ", ") + ". Disable the existing rule first."
                return
            }
        }
        var updated = rules
        guard let index = updated.firstIndex(where: { $0.id == rule.id }) else { return }
        updated[index].enabled.toggle(); _ = persist(updated)
    }
    func delete(_ id: UUID) {
        if persist(rules.filter { $0.id != id }), selected == id { selected = rules.first?.id }
    }
    private func persist(_ updated: [SavedRule]) -> Bool {
        guard !loadFailed else { warning = "Resolve the existing rules.json load error before saving. Open the rules folder to inspect the preserved file."; return false }
        do { try store.save(updated); rules = updated; engine.rules = updated; warning = ""; return true }
        catch { warning = error.localizedDescription; return false }
    }
    func startEngine() {
        do { try engine.start(); engineRunning = true; lastEvent = "Listening for gestures" }
        catch { warning = error.localizedDescription }
    }
    func stopEngine() { engine.stop(); engineRunning = false; lastEvent = "Engine paused" }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func openRulesFolder() { NSWorkspace.shared.open(store.url.deletingLastPathComponent()) }
}
