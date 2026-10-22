import SwiftUI

public struct ModelProviderSettingsView: View {
    @ObservedObject private var controller: ModelProviderController
    public init(controller: ModelProviderController) { self.controller = controller }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model").font(.title2)
            Picker("Provider", selection: $controller.selection) {
                ForEach(ModelProviderKind.allCases) { value in Text(value.label).tag(value) }
            }
            switch controller.selection {
            case .appleIntelligence:
                Text("Create rules with Apple's on-device model. Requires macOS 26 or later and Apple Intelligence enabled.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Refresh status") { Task { await controller.refresh() } }
            case .customLocal:
                Text("Run an MLX model from a local folder. Choose a Python environment with mlx-lm and Outlines installed.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    TextField("Python executable", text: $controller.python)
                    Button("Choose environment…", action: controller.choosePythonEnvironment)
                }
                HStack {
                    TextField("Model folder", text: $controller.localModelPath)
                    Button("Choose model…", action: controller.chooseLocalModel)
                }
                HStack {
                    Button("Load model") { Task { await controller.loadLocalModel() } }
                    Button("Unload") { Task { await controller.unloadLocalModel() } }
                }
            case .api:
                Text("Use an OpenAI-compatible Chat Completions endpoint with strict JSON-schema output.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("API base URL, such as https://api.example.com/v1", text: $controller.apiBaseURL)
                TextField("Model ID", text: $controller.apiModel)
                Toggle("Endpoint requires an API key", isOn: $controller.apiRequiresKey)
                if controller.apiRequiresKey {
                    SecureField("API key", text: $controller.apiKeyInput)
                    HStack {
                        Button("Save key in Keychain") { Task { await controller.saveAPIKey() } }.disabled(controller.apiKeyInput.isEmpty)
                        if controller.hasSavedAPIKey {
                            Text("Key saved").font(.caption).foregroundStyle(.secondary)
                            Button("Remove key", role: .destructive) { Task { await controller.removeAPIKey() } }
                        }
                    }
                }
                Text(controller.apiConfiguration.disclosure).font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                if controller.busy { ProgressView().controlSize(.small) }
                Text(controller.statusLabel).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if !controller.problem.isEmpty { Text(controller.problem).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
        }.textFieldStyle(.roundedBorder).disabled(controller.busy)
    }
}
