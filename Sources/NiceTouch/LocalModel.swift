import Foundation
import NiceTouchCore
import NiceTouchModels
import Darwin

/// Inference lives in an actor and a separate MLX process. Never used by RuntimeEngine.
actor LocalModel: CustomLocalModelBackend {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()
    func unload() {
        if let process, process.isRunning { process.terminate() }
        try? input?.close(); try? output?.close()
        process = nil; input = nil; output = nil; pending = Data()
    }
    func load(python: String, model: String) throws {
        unload()
        guard python.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: python) else { throw RuleError("Choose the absolute path to your MLX virtual environment's Python executable.") }
        guard model.hasPrefix("/"), FileManager.default.fileExists(atPath: model + "/config.json") else { throw RuleError("Choose a local MLX model directory containing config.json.") }
        guard let script = AppResources.bundle.url(forResource: "mlx_worker", withExtension: "py") else { throw RuleError("The bundled MLX worker is missing. Rebuild the app.") }
        let p = Process(); p.executableURL = URL(fileURLWithPath: python); p.arguments = ["-u", script.path, model]
        let incoming = Pipe(), outgoing = Pipe()
        p.standardInput = incoming; p.standardOutput = outgoing; p.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"; env["TRANSFORMERS_OFFLINE"] = "1"; env["TOKENIZERS_PARALLELISM"] = "false"
        p.environment = env
        try p.run()
        incoming.fileHandleForReading.closeFile()
        outgoing.fileHandleForWriting.closeFile()
        process = p; input = incoming.fileHandleForWriting; output = outgoing.fileHandleForReading
        do {
            let reply = try readReply()
            guard reply["ready"] as? Bool == true else { throw RuleError(reply["error"] as? String ?? "MLX failed to load.") }
        } catch { unload(); throw error }
    }
    func generate(command: String, feedback: String, apps: String) throws -> String {
        guard let process, process.isRunning, let input else { throw RuleError("Load a local model first.") }
        guard let promptURL = AppResources.bundle.url(forResource: "system-prompt", withExtension: "txt") else {
            throw RuleError("The bundled system prompt is missing. Rebuild the app.")
        }
        let system = try String(contentsOf: promptURL, encoding: .utf8) + "\nInstalled app bundle identifiers: " + apps
        let payload = ["system": system, "prompt": command + (feedback.isEmpty ? "" : "\nPrevious output failed validation. Repair it: " + feedback)]
        var data = try JSONSerialization.data(withJSONObject: payload); data.append(10)
        try input.write(contentsOf: data)
        let reply = try readReply()
        if let error = reply["error"] as? String { throw RuleError(error) }
        guard let text = reply["text"] as? String else { throw RuleError("MLX returned an invalid protocol response.") }
        return text
    }
    private func readReply() throws -> [String: Any] {
        guard let process, let output else { throw RuleError("MLX worker is unavailable.") }
        let deadline = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: deadline)
        defer { deadline.cancel() }
        while true {
            if let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline); pending.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw RuleError("Invalid MLX protocol response.") }
                return object
            }
            let chunk = output.availableData
            guard !chunk.isEmpty else { throw RuleError("MLX worker stopped or exceeded its 120-second limit. Check the Python path, model files and available memory, then reload.") }
            pending.append(chunk)
            guard pending.count <= 64_000 else { throw RuleError("MLX output exceeded 64 KB.") }
        }
    }
}
