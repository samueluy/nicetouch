import Foundation

/// NiceTouch's existing LocalModel actor can adopt this protocol without moving
/// Python, model weights or inference into the runtime gesture engine.
public protocol CustomLocalModelBackend: Sendable {
    func load(python: String, model: String) async throws
    func unload() async
    func generate(command: String, feedback: String, apps: String) async throws -> String
}
public actor CustomLocalModelProvider: RuleModelProvider {
    private let backend: any CustomLocalModelBackend
    private var loaded = false
    private var loading = false
    private var epoch: UInt64 = 0
    public init(backend: any CustomLocalModelBackend) { self.backend = backend }
    public func load(python: String, model: String) async throws {
        guard !loading else { throw RuleModelError.unavailable("A local model is loading.") }
        epoch &+= 1; let requestEpoch = epoch
        loaded = false; loading = true
        defer { loading = false }
        try await backend.load(python: python, model: model)
        guard epoch == requestEpoch else { throw CancellationError() }
        loaded = true
    }
    public func unload() async { epoch &+= 1; loaded = false; await backend.unload() }
    public func readiness() async -> ModelReadiness {
        if loading { return .needsConfiguration("Loading local model…") }
        return loaded ? .ready : .needsConfiguration("Choose and load a local MLX model.")
    }
    public func generate(_ request: RuleModelRequest) async throws -> String {
        guard loaded else { throw RuleModelError.unavailable("Load a local MLX model first.") }
        do { return try await backend.generate(command: request.command, feedback: request.feedback, apps: request.localAppContext) }
        catch { loaded = false; throw error }
    }
}
