import Foundation
import SwiftUI
import AppKit

/// UI state only. The gesture engine must not hold or call this controller.
@MainActor public final class ModelProviderController: ObservableObject {
    @Published public var selection: ModelProviderKind {
        didSet { ModelProviderPreferences.save(selection, in: defaults); apiKeyInput = ""; scheduleRefresh() }
    }
    @Published public var apiBaseURL: String { didSet { apiKeyInput = ""; saveAPIConfiguration(); scheduleRefresh() } }
    @Published public var apiModel: String { didSet { saveAPIConfiguration(); scheduleRefresh() } }
    @Published public var apiRequiresKey: Bool { didSet { saveAPIConfiguration(); scheduleRefresh() } }
    @Published public var apiKeyInput = ""
    @Published public var python: String { didSet { defaults.set(python, forKey: "python") } }
    @Published public var localModelPath: String { didSet { defaults.set(localModelPath, forKey: "modelPath") } }
    @Published public private(set) var status: ModelReadiness = .unavailable("Checking model availability…")
    @Published public private(set) var busy = false
    @Published public private(set) var problem = ""
    @Published public private(set) var hasSavedAPIKey = false
    @Published public private(set) var activity = ""
    private let defaults: UserDefaults
    private let secrets: any APISecretStore
    private let customLocal: CustomLocalModelProvider?
    private var refreshRevision: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private static let apiConfigKey = "NiceTouch.apiConfiguration"
    public init(customLocal: CustomLocalModelProvider? = nil, defaults: UserDefaults = .standard, secrets: any APISecretStore = KeychainAPISecretStore()) {
        self.customLocal = customLocal; self.defaults = defaults; self.secrets = secrets
        selection = ModelProviderPreferences.selection(in: defaults)
        let saved = defaults.data(forKey: Self.apiConfigKey).flatMap { try? JSONDecoder().decode(APIConfiguration.self, from: $0) } ?? APIConfiguration()
        apiBaseURL = saved.baseURL; apiModel = saved.model; apiRequiresKey = saved.requiresAPIKey
        python = defaults.string(forKey: "python") ?? ""
        localModelPath = defaults.string(forKey: "modelPath") ?? ""
        scheduleRefresh()
    }
    public var apiConfiguration: APIConfiguration { APIConfiguration(baseURL: apiBaseURL, model: apiModel, requiresAPIKey: apiRequiresKey) }
    public var statusLabel: String {
        if busy { return activity }
        guard status.canGenerate else { return status.message }
        switch selection {
        case .appleIntelligence: return "Apple Intelligence ready"
        case .customLocal: return "Local model loaded"
        case .api: return "API ready · \((try? apiConfiguration.endpoint().host) ?? "endpoint")"
        }
    }
    public var privacyLabel: String {
        switch selection {
        case .appleIntelligence: return "Apple Intelligence on this Mac"
        case .customLocal: return "Local model on this Mac"
        case .api: return "API · \((try? apiConfiguration.endpoint().host) ?? "configure endpoint")"
        }
    }
    private func registry() -> ModelProviderRegistry {
        let local: any RuleModelProvider = customLocal ?? UnavailableRuleModel("Connect the existing MLX backend to load a custom local model.")
        return ModelProviderRegistry(customLocal: local, api: APIRuleProvider(configuration: apiConfiguration, secrets: secrets))
    }
    private func saveAPIConfiguration() {
        if let data = try? JSONEncoder().encode(apiConfiguration) { defaults.set(data, forKey: Self.apiConfigKey) }
    }
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshRevision &+= 1
        status = .unavailable("Checking model availability…"); hasSavedAPIKey = false
        refreshTask = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            self.refreshTask = nil
            await self.refresh()
        }
    }
    public func refresh() async {
        refreshTask?.cancel(); refreshTask = nil
        refreshRevision &+= 1; let revision = refreshRevision
        let selected = selection, service = registry(), config = apiConfiguration, store = secrets
        let result = await service.readiness(for: selected)
        let hasKey: Bool
        if selected == .api, let account = try? config.credentialAccount() {
            hasKey = await Task.detached { (try? store.secret(account: account))?.isEmpty == false }.value
        } else { hasKey = false }
        guard !Task.isCancelled, revision == refreshRevision, selection == selected else { return }
        status = result; hasSavedAPIKey = hasKey
    }
    public func generate(command: String, feedback: String = "", localAppContext: String = "") async throws -> String {
        guard !busy else { throw RuleModelError.unavailable("Wait for the current model operation to finish.") }
        let selected = selection, service = registry()
        let request = try RuleModelRequest(command: command, feedback: feedback, localAppContext: localAppContext)
        busy = true; problem = ""; activity = selected == .api ? "Waiting for API…" : "Generating rule on this Mac…"
        defer { busy = false; activity = "" }
        do { return try await service.generate(request, using: selected) }
        catch { problem = error.localizedDescription; throw error }
    }
    public func author(command: String, localAppContext: String = "", knownApps: [String: String] = [:], validate: @Sendable (String) throws -> Void) async throws -> String {
        guard !busy else { throw RuleModelError.unavailable("Wait for the current model operation to finish.") }
        let selected = selection, service = registry()
        let request = try RuleModelRequest(command: command, localAppContext: localAppContext, knownApps: knownApps)
        busy = true; problem = ""; activity = selected == .api ? "Waiting for API…" : "Generating rule on this Mac…"
        defer { busy = false; activity = "" }
        do { return try await service.author(request, using: selected, validate: validate) }
        catch { problem = error.localizedDescription; throw error }
    }
    public func saveAPIKey() async {
        guard !busy else { return }
        do {
            let config = apiConfiguration; try config.validate()
            let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key.unicodeScalars.allSatisfy({ (33...126).contains(Int($0.value)) }) else { throw RuleModelError.invalidConfiguration("Enter a valid API key.") }
            let account = try config.credentialAccount(), store = secrets
            busy = true; activity = "Saving API key…"; problem = ""
            defer { busy = false; activity = "" }
            try await Task.detached { try store.setSecret(key, account: account) }.value
            apiKeyInput = ""
            await refresh()
        } catch { problem = error.localizedDescription }
    }
    public func removeAPIKey() async {
        guard !busy else { return }
        do {
            let account = try apiConfiguration.credentialAccount(), store = secrets
            busy = true; activity = "Removing API key…"; problem = ""
            defer { busy = false; activity = "" }
            try await Task.detached { try store.deleteSecret(account: account) }.value
            apiKeyInput = ""; await refresh()
        } catch { problem = error.localizedDescription }
    }
    public func loadLocalModel() async {
        guard !busy else { return }
        guard let customLocal else { problem = "The MLX backend is not connected."; return }
        busy = true; activity = "Loading local model…"; problem = ""
        defer { busy = false; activity = "" }
        do { try await customLocal.load(python: python, model: localModelPath); await refresh() }
        catch { problem = error.localizedDescription; await refresh() }
    }
    public func unloadLocalModel() async {
        guard !busy, let customLocal else { return }
        busy = true; activity = "Unloading local model…"
        await customLocal.unload(); await refresh()
        busy = false; activity = ""
    }
    public func choosePythonEnvironment() {
        let panel = NSOpenPanel()
        panel.title = "Choose MLX Python environment"; panel.message = "Select the virtual environment folder containing bin/python."
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let folder = panel.url { python = folder.appendingPathComponent("bin/python").path }
    }
    public func chooseLocalModel() {
        let panel = NSOpenPanel()
        panel.title = "Choose local MLX model"; panel.message = "Select the folder containing config.json and the model weights."
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let folder = panel.url { localModelPath = folder.path }
    }
}
