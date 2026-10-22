import AppKit
import ServiceManagement
import SwiftUI

@MainActor protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

@MainActor struct MainAppLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
}

@MainActor final class StartupController: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var busy = false
    @Published private(set) var problem = ""
    @Published var showPrompt = false
    let isPackagedApp: Bool
    private let service: any LoginItemService
    private let defaults: UserDefaults
    private static let promptKey = "NiceTouch.didAskOpenAtLogin"

    init(service: (any LoginItemService)? = nil, defaults: UserDefaults = .standard,
         isPackagedApp: Bool = Bundle.main.bundleURL.pathExtension == "app") {
        self.service = service ?? MainAppLoginItemService(); self.defaults = defaults; self.isPackagedApp = isPackagedApp
    }

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    var statusMessage: String {
        if !isPackagedApp { return "Open at login is available in the packaged NiceTouch.app build." }
        switch status {
        case .enabled: return "NiceTouch will open in the menu bar when you log in."
        case .requiresApproval: return "Allow NiceTouch in System Settings → General → Login Items."
        case .notFound: return "Open at login is not registered for this copy. Keep NiceTouch at a stable location before enabling it."
        case .notRegistered: return "NiceTouch will open when you launch it."
        @unknown default: return "Check NiceTouch in System Settings → General → Login Items."
        }
    }
    func refresh() { if isPackagedApp { status = service.status } }
    func preparePrompt() {
        refresh()
        guard isPackagedApp, !defaults.bool(forKey: Self.promptKey) else { return }
        guard status == .notRegistered || status == .notFound else {
            if isRegistered { defaults.set(true, forKey: Self.promptKey) }
            return
        }
        showPrompt = true
    }
    func declinePrompt() {
        defaults.set(true, forKey: Self.promptKey); showPrompt = false
    }
    func acceptPrompt() async {
        defaults.set(true, forKey: Self.promptKey); showPrompt = false
        await setEnabled(true)
    }
    func setEnabled(_ enabled: Bool) async {
        guard isPackagedApp, !busy else { return }
        busy = true; problem = ""
        defer { busy = false; refresh() }
        do {
            refresh()
            if enabled && !isRegistered { try service.register() }
            else if !enabled && isRegistered { try await service.unregister() }
        } catch { problem = "Could not change Open at login. " + error.localizedDescription }
    }
    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
