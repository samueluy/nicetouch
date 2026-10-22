import SwiftUI
import TrackpadBridge

@main struct NiceTouchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        if CommandLine.arguments.contains("--check-resources") {
            for (name, ext) in [("mlx_worker", "py"), ("rule.schema", "json"), ("system-prompt", "txt")] {
                guard let url = AppResources.bundle.url(forResource: name, withExtension: ext),
                      FileManager.default.fileExists(atPath: url.path) else {
                    fputs("Missing resource: \(name).\(ext)\n", stderr); exit(1)
                }
                print(url.path)
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--check-trackpad") {
            let available = NTStart { _, _, _, _, _ in }
            NTStop()
            print(available ? "Built-in trackpad opened and reports running; capture stopped." : "Built-in trackpad unavailable or private API unsupported.")
            exit(available ? 0 : 1)
        }
    }
    var body: some Scene {
        MenuBarExtra("NiceTouch", systemImage: "hand.draw") {
            MenuContent(openWindow: delegate.openMainWindow).environmentObject(delegate.state)
        }
    }
}
private struct MenuContent: View {
    @EnvironmentObject var state: AppState
    let openWindow: () -> Void
    var body: some View {
        Button("Open NiceTouch", action: openWindow)
        Divider()
        Text(state.engineRunning ? "Gestures active" : "Gestures paused")
        Toggle("Require Fn key", isOn: $state.requireFn)
        Button(state.engineRunning ? "Pause gestures" : "Start gestures") {
            if state.engineRunning { state.stopEngine() } else { state.startEngine(); if !state.warning.isEmpty { openWindow() } }
        }
        Divider()
        Button("Quit NiceTouch") { state.stopEngine(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
