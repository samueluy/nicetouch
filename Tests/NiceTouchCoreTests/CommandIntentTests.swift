import XCTest
@testable import NiceTouchCore

final class CommandIntentTests: XCTestCase {
    func rule(app: String = "com.google.Chrome", direction: Direction = .left, zone: Zone = .anywhere, action: RuleAction = .previousTab) -> RuleDefinition {
        RuleDefinition(name: "Test", app: app, gesture: Gesture(kind: .swipe, fingers: 3, direction: direction, zone: zone), action: action)
    }
    func testIncompleteAndCompoundCommandsAskForDetails() {
        for command in ["Make my trackpad better", "Swipe three fingers in Chrome to switch tabs", "Tap four fingers in Safari to run my script", "Swipe three fingers left in Chrome for previous tab and next tab", "Swipe three or four fingers left in Chrome for previous tab"] {
            XCTAssertNotNil(CommandIntentValidator.clarification(for: command), command)
        }
    }
    func testCompleteCommandsKeepTheirFacts() throws {
        XCTAssertNoThrow(try CommandIntentValidator.validate(rule(), command: "Three-finger swipe left in Chrome for previous tab"))
        XCTAssertThrowsError(try CommandIntentValidator.validate(rule(direction: .right), command: "Three-finger swipe left in Chrome for previous tab"))
        XCTAssertThrowsError(try CommandIntentValidator.validate(rule(action: .nextTab), command: "Three-finger swipe left in Chrome for previous tab"))
        XCTAssertThrowsError(try CommandIntentValidator.validate(rule(app: "com.apple.Safari"), command: "Three-finger swipe left in Chrome for previous tab"))
    }
    func testGlobalScopeCannotBecomeSpecificApp() throws {
        let command = "Swipe three fingers left in all apps for previous tab"
        XCTAssertNoThrow(try CommandIntentValidator.validate(rule(app: "*"), command: command))
        XCTAssertThrowsError(try CommandIntentValidator.validate(rule(), command: command))
    }
    func testMissingScopeAsksInsteadOfAssumingChromeOrGlobal() {
        for app in ["*", "com.google.Chrome"] {
            XCTAssertThrowsError(try CommandIntentValidator.validate(rule(app: app), command: "Swipe three fingers left for previous tab")) { error in
                guard case CommandIntentError.clarification = error else { return XCTFail("Expected clarification: \(error)") }
            }
        }
    }
    func testZoneAndDirectionAreIndependent() throws {
        let command = "Swipe three fingers left from the top edge in Chrome for previous tab"
        XCTAssertNoThrow(try CommandIntentValidator.validate(rule(zone: .top), command: command))
        XCTAssertThrowsError(try CommandIntentValidator.validate(rule(), command: command))
        XCTAssertThrowsError(try CommandIntentValidator.validate(rule(zone: .top), command: "Swipe three fingers left in Chrome for previous tab"))
    }
    func testCustomAppDisplayNameCanGroundBundleID() throws {
        XCTAssertNoThrow(try CommandIntentValidator.validate(rule(app: "org.example.Editor"), command: "Swipe three fingers left in My Editor for previous tab", knownApps: ["org.example.Editor": "My Editor"]))
    }
    func testReopenClosedTabDoesNotCountAsTwoActions() throws {
        let command = "Tap four fingers in the top zone in Safari to reopen the closed tab"
        XCTAssertNil(CommandIntentValidator.clarification(for: command))
        let value = RuleDefinition(name: "Reopen", app: "com.apple.Safari", gesture: Gesture(kind: .tap, fingers: 4, direction: .none, zone: .top), action: .reopenTab)
        XCTAssertNoThrow(try CommandIntentValidator.validate(value, command: command))
    }
}
