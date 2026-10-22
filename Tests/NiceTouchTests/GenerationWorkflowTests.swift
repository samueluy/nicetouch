import XCTest
import NiceTouchCore
import NiceTouchModels
@testable import NiceTouch

/// Ignores task cancellation so tests can prove that a late result is discarded.
private actor DelayedRuleProvider: RuleModelProvider {
    private var continuation: CheckedContinuation<String, Never>?
    private var requests: [RuleModelRequest] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var pauseNext = true
    func readiness() async -> ModelReadiness { .ready }
    func generate(_ request: RuleModelRequest) async throws -> String {
        requests.append(request)
        let ready = waiters.filter { $0.0 <= requests.count }; waiters.removeAll { $0.0 <= requests.count }
        ready.forEach { $0.1.resume() }
        guard pauseNext else { return "{}" }
        pauseNext = false
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitForRequests(_ count: Int = 1) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func reply(_ text: String) { let pending = continuation; continuation = nil; pending?.resume(returning: text) }
    func pauseNextRequest() { pauseNext = true }
    func count() -> Int { requests.count }
}

private actor FailedLocalBackend: CustomLocalModelBackend {
    func load(python: String, model: String) async throws {}
    func unload() async {}
    func generate(command: String, feedback: String, apps: String) async throws -> String {
        throw RuleModelError.unavailable("The local worker exited.")
    }
}

@MainActor final class GenerationWorkflowTests: XCTestCase {
    private func fixture() async throws -> (AppState, DelayedRuleProvider, RuleStore, UserDefaults) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NiceTouchGeneration-" + UUID().uuidString)
        let store = RuleStore(url: folder.appendingPathComponent("rules.json")); try store.save([])
        let suite = "org.nicetouch.generation.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { try? FileManager.default.removeItem(at: folder); defaults.removePersistentDomain(forName: suite) }
        let provider = DelayedRuleProvider()
        let models = ModelProviderController(defaults: defaults, providers: ModelProviderRegistry(apple: provider))
        await models.refresh()
        return (AppState(store: store, models: models, defaults: defaults), provider, store, defaults)
    }
    func definition(action: RuleAction = .copy, direction: Direction = .left) -> RuleDefinition {
        RuleDefinition(name: action.label, app: "com.google.Chrome", gesture: Gesture(kind: .swipe, fingers: 3, direction: direction), action: action)
    }
    let command = "When I swipe three fingers left in Chrome, copy."
    func testFullGenerationRequiresReviewBeforeSaving() async throws {
        let (state, provider, store, _) = try await fixture()
        state.command = command; state.generate()
        let task = try XCTUnwrap(state.generationTask)
        await provider.waitForRequests(); await provider.reply(definition().json); await task.value
        XCTAssertEqual(state.draft, definition()); XCTAssertFalse(state.busy)
        XCTAssertTrue(try store.load().isEmpty); XCTAssertTrue(state.rules.isEmpty)
        state.saveDraft()
        XCTAssertEqual(try store.load().map(\.definition), [definition()]); XCTAssertNil(state.draft)
    }
    func testEditingCommandDiscardsLateReplyAndNextRequestCanSucceed() async throws {
        let (state, provider, store, _) = try await fixture()
        state.command = command; state.generate()
        let oldTask = try XCTUnwrap(state.generationTask)
        await provider.waitForRequests()
        state.command = "When I swipe three fingers right in Chrome, paste."
        XCTAssertFalse(state.busy); XCTAssertNil(state.generationTask)
        await provider.reply(definition().json); await oldTask.value
        XCTAssertNil(state.draft); XCTAssertTrue(state.rawJSON.isEmpty)
        XCTAssertTrue(state.warning.isEmpty); XCTAssertTrue(try store.load().isEmpty)
        await provider.pauseNextRequest(); state.generate()
        let newTask = try XCTUnwrap(state.generationTask)
        await provider.waitForRequests(2)
        await provider.reply(definition(action: .paste, direction: .right).json); await newTask.value
        XCTAssertEqual(state.draft?.action, .paste); XCTAssertEqual(state.draft?.gesture.direction, .right)
    }
    func testSelectingSavedRuleCannotBeOverwrittenByLateGeneration() async throws {
        let (state, provider, store, _) = try await fixture()
        state.draft = definition(); state.saveDraft()
        let selected = try XCTUnwrap(state.selected), saved = state.rules
        state.command = command; state.generate()
        let task = try XCTUnwrap(state.generationTask)
        await provider.waitForRequests()
        state.selected = selected; state.discardPreview()
        await provider.reply(definition().json); await task.value
        XCTAssertNil(state.draft); XCTAssertEqual(state.selected, selected)
        XCTAssertEqual(state.selectedRule, definition()); XCTAssertEqual(try store.load(), saved)
    }
    func testCancelDoesNotStartAnotherProviderCallOrShowRepairError() async throws {
        let (state, provider, store, _) = try await fixture()
        state.command = command; state.generate()
        let task = try XCTUnwrap(state.generationTask)
        await provider.waitForRequests()
        state.cancelGeneration()
        XCTAssertTrue(state.models.busy); XCTAssertTrue(state.models.activity.contains("Cancelling"))
        state.generate(); XCTAssertNil(state.generationTask)
        await provider.reply("{\"unexpected\":true}"); await task.value
        let count = await provider.count(); XCTAssertEqual(count, 1)
        XCTAssertFalse(state.models.busy); XCTAssertTrue(state.models.problem.isEmpty)
        XCTAssertNil(state.draft); XCTAssertTrue(state.warning.isEmpty); XCTAssertTrue(try store.load().isEmpty)
    }
    func testEditingCompletedPreviewInvalidatesItBeforeSave() async throws {
        let (state, provider, store, _) = try await fixture()
        state.command = command; state.generate()
        let task = try XCTUnwrap(state.generationTask)
        await provider.waitForRequests(); await provider.reply(definition().json); await task.value
        XCTAssertNotNil(state.draft)
        state.command = "When I swipe three fingers right in Chrome, paste."
        state.saveDraft()
        XCTAssertNil(state.draft); XCTAssertTrue(state.rawJSON.isEmpty); XCTAssertTrue(try store.load().isEmpty)
    }
    func testFailedLocalGenerationClearsReadyStatus() async throws {
        let (_, _, _, defaults) = try await fixture()
        let local = CustomLocalModelProvider(backend: FailedLocalBackend())
        try await local.load(python: "/test/python", model: "/test/model")
        let models = ModelProviderController(customLocal: local, defaults: defaults, providers: ModelProviderRegistry(customLocal: local))
        models.selection = .customLocal; await models.refresh()
        XCTAssertTrue(models.status.canGenerate)
        do {
            _ = try await models.author(command: command) { _ = try RuleValidator.parse($0) }
            XCTFail("Expected local worker failure")
        } catch {}
        XCTAssertFalse(models.status.canGenerate)
        XCTAssertFalse(models.busy)
        XCTAssertTrue(models.problem.contains("worker exited"))
        XCTAssertFalse(models.statusLabel.contains("loaded"))
    }
    func testFnPreferenceUsesInjectedSettingsAndDefaultsToRequired() async throws {
        let (state, _, store, defaults) = try await fixture()
        XCTAssertTrue(state.requireFn)
        state.requireFn = false
        let reopened = AppState(store: store, models: state.models, defaults: defaults)
        XCTAssertFalse(reopened.requireFn); XCTAssertEqual(defaults.object(forKey: "requireFn") as? Bool, false)
    }
}
