import XCTest
import NiceTouchCore
@testable import NiceTouch

@MainActor final class RuleWorkflowTests: XCTestCase {
    func temporaryStore() throws -> RuleStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NiceTouchWorkflow-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return RuleStore(url: folder.appendingPathComponent("rules.json"))
    }
    func definition(_ action: RuleAction = .copy) -> RuleDefinition {
        RuleDefinition(name: action.label, app: "com.google.Chrome", gesture: Gesture(kind: .swipe, fingers: 3, direction: .left), action: action)
    }
    func testPreviewSaveAndRelaunchPreserveEnabledRuleAndSelection() async throws {
        let store = try temporaryStore(); try store.save([])
        let state = AppState(store: store)
        state.command = "When I swipe three fingers left in Chrome, copy."
        state.rawJSON = definition().json
        state.draft = try RuleValidator.parse(state.rawJSON)
        XCTAssertTrue(try store.load().isEmpty, "Preview alone must not persist a rule")
        state.saveDraft()
        let saved = try XCTUnwrap(state.rules.first)
        XCTAssertTrue(saved.enabled); XCTAssertEqual(saved.definition, definition())
        XCTAssertEqual(state.selected, saved.id); XCTAssertNil(state.draft)
        XCTAssertTrue(state.command.isEmpty); XCTAssertTrue(state.rawJSON.isEmpty)
        let reopened = AppState(store: store)
        XCTAssertEqual(reopened.rules, [saved]); XCTAssertEqual(reopened.selected, saved.id)
    }
    func testConflictPreviewCannotOverwritePersistedCollection() async throws {
        let store = try temporaryStore(), saved = SavedRule(definition: definition())
        try store.save([saved]); let before = try Data(contentsOf: store.url)
        let state = AppState(store: store); state.draft = definition(.paste)
        state.saveDraft()
        XCTAssertEqual(state.rules, [saved]); XCTAssertNotNil(state.draft)
        XCTAssertTrue(state.warning.contains("assigned to"))
        XCTAssertEqual(try Data(contentsOf: store.url), before)
    }
    func testConflictingDisabledRuleNeedsExistingRuleDisabledFirst() async throws {
        let store = try temporaryStore()
        let first = SavedRule(definition: definition()), second = SavedRule(enabled: false, definition: definition(.paste))
        try store.save([first, second])
        let state = AppState(store: store)
        state.toggle(second)
        XCTAssertEqual(try store.load(), [first, second]); XCTAssertTrue(state.warning.contains("Cannot enable"))
        state.toggle(first); state.toggle(second)
        let reloaded = AppState(store: store)
        XCTAssertEqual(reloaded.rules.map(\.enabled), [false, true])
        XCTAssertEqual(reloaded.rules.map(\.id), [first.id, second.id])
    }
    func testCorruptFileSurvivesAttemptToSavePreview() async throws {
        let store = try temporaryStore(), original = Data("{broken configuration".utf8)
        try original.write(to: store.url)
        let state = AppState(store: store)
        state.draft = definition(); state.saveDraft()
        XCTAssertEqual(try Data(contentsOf: store.url), original)
        XCTAssertTrue(state.warning.contains("load error")); XCTAssertTrue(state.rules.isEmpty)
    }
}
