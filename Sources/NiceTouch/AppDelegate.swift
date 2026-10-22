import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()
    let startup = StartupController()
    private var mainWindow: NSWindow?
    private var finishedLaunching = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Keep the app out of the Dock, including when launched through SwiftPM.
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        finishedLaunching = true
        // Login launches create only the menu-bar item. No window or prompt.
        if !Self.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent) { openMainWindow() }
    }
    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
    func openMainWindow() {
        if mainWindow == nil {
            let controller = NSHostingController(rootView: MainView()
                .environmentObject(state).environmentObject(state.models).environmentObject(startup))
            let window = NSWindow(contentViewController: controller)
            window.title = "NiceTouch"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 1240, height: 860))
            window.minSize = NSSize(width: 1080, height: 760)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("NiceTouchMainWindow")
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if finishedLaunching { openMainWindow() }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { state.stopEngine() }
}
