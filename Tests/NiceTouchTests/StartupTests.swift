import XCTest
import ServiceManagement
import Carbon.HIToolbox
@testable import NiceTouch

@MainActor private final class LoginItemFixture: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrations = 0
    var removals = 0
    var needsApproval = false
    var fails = false
    func register() throws {
        registrations += 1
        if fails { throw NSError(domain: "StartupTest", code: 1) }
        status = needsApproval ? .requiresApproval : .enabled
    }
    func unregister() async throws { removals += 1; status = .notRegistered }
}
@MainActor final class StartupTests: XCTestCase {
    func testLoginLaunchDetectionKeepsOrdinaryLaunchesInteractive() async {
        let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEOpenApplication,
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        XCTAssertFalse(AppDelegate.isLoginLaunch(nil))
        XCTAssertFalse(AppDelegate.isLoginLaunch(event))
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        XCTAssertTrue(AppDelegate.isLoginLaunch(event))
    }
    func defaults() -> UserDefaults { UserDefaults(suiteName: "org.nicetouch.startup.tests.\(UUID().uuidString)")! }
    func testPromptDoesNotRegisterAndDeclinePersists() async {
        let service = LoginItemFixture(), preferences = defaults()
        let controller = StartupController(service: service, defaults: preferences, isPackagedApp: true)
        controller.preparePrompt()
        XCTAssertTrue(controller.showPrompt); XCTAssertEqual(service.registrations, 0)
        controller.declinePrompt()
        let relaunched = StartupController(service: service, defaults: preferences, isPackagedApp: true)
        relaunched.preparePrompt()
        XCTAssertFalse(relaunched.showPrompt); XCTAssertEqual(service.registrations, 0)
    }
    func testAcceptRegistersAndDoesNotAskAgain() async {
        let service = LoginItemFixture(), preferences = defaults()
        let controller = StartupController(service: service, defaults: preferences, isPackagedApp: true)
        controller.preparePrompt(); await controller.acceptPrompt()
        XCTAssertTrue(controller.isRegistered); XCTAssertFalse(controller.showPrompt)
        XCTAssertEqual(service.registrations, 1)
        let relaunched = StartupController(service: service, defaults: preferences, isPackagedApp: true)
        relaunched.preparePrompt(); XCTAssertFalse(relaunched.showPrompt)
    }
    func testApprovalIsReportedInsteadOfClaimingEnabled() async {
        let service = LoginItemFixture(); service.needsApproval = true
        let controller = StartupController(service: service, defaults: defaults(), isPackagedApp: true)
        await controller.setEnabled(true)
        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertTrue(controller.statusMessage.contains("Allow NiceTouch"))
        await controller.setEnabled(true); XCTAssertEqual(service.registrations, 1)
    }
    func testDisablingUnregistersAndExternalChangesRefresh() async {
        let service = LoginItemFixture(); service.status = .enabled
        let controller = StartupController(service: service, defaults: defaults(), isPackagedApp: true)
        controller.preparePrompt(); XCTAssertFalse(controller.showPrompt)
        await controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered); XCTAssertEqual(service.removals, 1)
        service.status = .requiresApproval; controller.refresh()
        XCTAssertEqual(controller.status, .requiresApproval)
    }
    func testFailedRegistrationShowsErrorAndSettingsCanRetry() async {
        let service = LoginItemFixture(); service.fails = true
        let controller = StartupController(service: service, defaults: defaults(), isPackagedApp: true)
        await controller.acceptPrompt()
        XCTAssertFalse(controller.isRegistered); XCTAssertFalse(controller.problem.isEmpty)
        XCTAssertFalse(controller.busy)
        service.fails = false; await controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered); XCTAssertTrue(controller.problem.isEmpty)
    }
    func testSwiftRunDoesNotPromptOrRegister() async {
        let service = LoginItemFixture()
        let controller = StartupController(service: service, defaults: defaults(), isPackagedApp: false)
        controller.preparePrompt(); await controller.setEnabled(true)
        XCTAssertFalse(controller.showPrompt); XCTAssertEqual(service.registrations, 0)
        XCTAssertTrue(controller.statusMessage.contains("packaged"))
    }
    func testUnregisteredCopyStillOffersStartupPrompt() async {
        let service = LoginItemFixture(); service.status = .notFound
        let controller = StartupController(service: service, defaults: defaults(), isPackagedApp: true)
        controller.preparePrompt()
        XCTAssertTrue(controller.showPrompt)
        await controller.acceptPrompt()
        XCTAssertEqual(service.registrations, 1)
        XCTAssertTrue(controller.isRegistered)
    }
}
