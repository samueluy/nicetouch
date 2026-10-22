import Foundation

enum AppResources {
    static var bundle: Bundle {
        // SwiftPM's generated accessor looks beside the executable or in the build
        // tree. A distributed .app keeps its resource bundle in Contents/Resources.
        if let resources = Bundle.main.resourceURL,
           let bundled = Bundle(url: resources.appendingPathComponent("NiceTouch_NiceTouch.bundle")) {
            return bundled
        }
        return Bundle.module
    }
}
