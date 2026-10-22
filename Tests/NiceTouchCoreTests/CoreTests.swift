import XCTest
@testable import NiceTouchCore

final class CoreTests: XCTestCase {
    func rule(app: String = "com.google.Chrome", zone: Zone = .anywhere, direction: Direction = .left) -> RuleDefinition {
        RuleDefinition(name: "Previous tab", app: app, gesture: Gesture(kind: .swipe, fingers: 3, direction: direction, zone: zone), action: .previousTab)
    }
    func testRoundTrip() throws { let r = rule(); XCTAssertEqual(try RuleValidator.parse(r.json), r) }
    func testRejectsDuplicateAndEscapedDuplicateKeys() {
        let text = String(rule().json.dropLast()) + ",\"app\":\"*\"}"
        XCTAssertThrowsError(try RuleValidator.parse(text))
        XCTAssertThrowsError(try RuleValidator.parse(text.replacingOccurrences(of: ",\"app\":", with: ",\"\\u0061pp\":")))
        let nested = rule().json.replacingOccurrences(of: "\"kind\" : \"swipe\"", with: "\"kind\":\"swipe\",\"kind\":\"tap\"")
        XCTAssertThrowsError(try RuleValidator.parse(nested))
    }
    func testEscapedStringsRoundTrip() throws {
        var r = rule(); r.name = "Tab \\\"previous\\\" \\ back"
        XCTAssertEqual(try RuleValidator.parse(r.json), r)
    }
    func testPersistedRulesRejectUnknownFields() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RuleStore(url: dir.appendingPathComponent("rules.json"))
        try store.save([SavedRule(definition: rule())])
        var array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [[String: Any]])
        array[0]["unexpected"] = true
        try JSONSerialization.data(withJSONObject: array).write(to: store.url)
        XCTAssertThrowsError(try store.load())
        array[0].removeValue(forKey: "unexpected")
        var definition = array[0]["definition"] as! [String: Any]; definition["script"] = "unsupported"; array[0]["definition"] = definition
        try JSONSerialization.data(withJSONObject: array).write(to: store.url)
        XCTAssertThrowsError(try store.load())
    }
    func testRejectsExtraFieldsAtEveryLevel() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rule().json.utf8)) as? [String: Any])
        object["script"] = "do something"
        XCTAssertThrowsError(try RuleValidator.parse(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self)))
        object.removeValue(forKey: "script")
        var g = object["gesture"] as! [String: Any]; g["pressure"] = 1; object["gesture"] = g
        XCTAssertThrowsError(try RuleValidator.parse(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self)))
    }
    func testRejectsMissingNullAndWrongTypes() {
        for text in ["{}", "null", "[]", "true", "```json\n" + rule().json + "\n```", rule().json.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : true"), rule().json.replacingOccurrences(of: "\"fingers\" : 3", with: "\"fingers\" : null")] {
            XCTAssertThrowsError(try RuleValidator.parse(text), text)
        }
    }
    func testRejectsInvalidValues() {
        var r = rule()
        r.version = 2; XCTAssertThrowsError(try RuleValidator.validate(r)); r.version = 1
        r.gesture.fingers = 2; XCTAssertThrowsError(try RuleValidator.validate(r)); r.gesture.fingers = 3
        r.gesture.direction = .none; XCTAssertThrowsError(try RuleValidator.validate(r)); r.gesture.direction = .left
        r.gesture.kind = .tap; XCTAssertThrowsError(try RuleValidator.validate(r)); r.gesture.kind = .swipe
        r.app = "Chrome"; XCTAssertThrowsError(try RuleValidator.validate(r)); r.app = "com.google.Chrome"
        r.name = " "; XCTAssertThrowsError(try RuleValidator.validate(r))
    }
    func testRejectsUnknownActionAndOversizedOutput() {
        XCTAssertThrowsError(try RuleValidator.parse(rule().json.replacingOccurrences(of: "previousTab", with: "shell")))
        XCTAssertThrowsError(try RuleValidator.parse(String(repeating: "x", count: 16385)))
    }
    func testSameGestureAndScopeConflict() { XCTAssertEqual(RuleValidator.conflicts(rule(), with: [SavedRule(definition: rule())]).count, 1) }
    func testPreviousAndNextTabCannotShareTheSameSwipe() throws {
        let previous = SavedRule(definition: rule())
        var nextDefinition = rule()
        nextDefinition.name = "Next tab"; nextDefinition.action = .nextTab
        let next = SavedRule(definition: nextDefinition)
        XCTAssertEqual(RuleValidator.conflicts(nextDefinition, with: [previous]).map(\.id), [previous.id])
        XCTAssertThrowsError(try RuleValidator.validateCollection([previous, next]))
        let disabledNext = SavedRule(enabled: false, definition: nextDefinition)
        XCTAssertNoThrow(try RuleValidator.validateCollection([previous, disabledNext]))
        var enabledNext = disabledNext; enabledNext.enabled = true
        XCTAssertThrowsError(try RuleValidator.validateCollection([previous, enabledNext]))
        var recognizer = GestureRecognizer()
        _ = recognizer.feed(points(0.7), time: 1)
        _ = recognizer.feed(points(0.4), time: 1.2)
        let event = try XCTUnwrap(recognizer.feed([], time: 1.3))
        XCTAssertNil(RuleMatcher.match(event, app: "com.google.Chrome", rules: [previous, next]))
        nextDefinition.gesture.direction = .right
        XCTAssertTrue(RuleValidator.conflicts(nextDefinition, with: [previous]).isEmpty)
    }
    func testGlobalScopeConflictsWithSpecificApp() {
        XCTAssertFalse(RuleValidator.conflicts(rule(), with: [SavedRule(definition: rule(app: "*"))]).isEmpty)
        XCTAssertFalse(RuleValidator.conflicts(rule(app: "*"), with: [SavedRule(definition: rule())]).isEmpty)
    }
    func testDifferentAppsDirectionsAndOppositeEdgesDoNotConflict() {
        XCTAssertTrue(RuleValidator.conflicts(rule(), with: [SavedRule(definition: rule(app: "com.apple.Safari"))]).isEmpty)
        XCTAssertTrue(RuleValidator.conflicts(rule(), with: [SavedRule(definition: rule(direction: .right))]).isEmpty)
        XCTAssertTrue(RuleValidator.conflicts(rule(zone: .left), with: [SavedRule(definition: rule(zone: .right))]).isEmpty)
    }
    func testCornerOverlapAndDisabledRules() {
        XCTAssertFalse(RuleValidator.conflicts(rule(zone: .left), with: [SavedRule(definition: rule(zone: .top))]).isEmpty)
        XCTAssertTrue(RuleValidator.conflicts(rule(), with: [SavedRule(enabled: false, definition: rule())]).isEmpty)
        let saved = SavedRule(definition: rule())
        XCTAssertTrue(RuleValidator.conflicts(rule(), with: [saved], excluding: saved.id).isEmpty)
    }
    func testCollectionRejectsDuplicateIDsAndConflicts() {
        let saved = SavedRule(definition: rule())
        XCTAssertThrowsError(try RuleValidator.validateCollection([saved, saved]))
        XCTAssertThrowsError(try RuleValidator.validateCollection([saved, SavedRule(definition: rule())]))
    }
    func points(_ x: Double, _ y: Double = 0.5, count: Int = 3) -> [Contact] { Array(repeating: Contact(x: x, y: y), count: count) }
    func testSwipeFiresOnceAfterLift() throws {
        var recognizer = GestureRecognizer()
        XCTAssertNil(recognizer.feed(points(0.7), time: 1))
        XCTAssertNil(recognizer.feed(points(0.4), time: 1.2))
        let event = try XCTUnwrap(recognizer.feed([], time: 1.3))
        XCTAssertEqual(event.gesture.direction, .left); XCTAssertEqual(event.gesture.kind, .swipe)
        XCTAssertEqual(event.x, 0.7, accuracy: 0.000001); XCTAssertNil(recognizer.feed([], time: 1.4))
    }
    func testTapAndVerticalSwipe() throws {
        var recognizer = GestureRecognizer()
        _ = recognizer.feed(points(0.5, count: 4), time: 1)
        XCTAssertEqual(recognizer.feed([], time: 1.2)?.gesture.kind, .tap)
        _ = recognizer.feed(points(0.5, 0.3), time: 2); _ = recognizer.feed(points(0.5, 0.6), time: 2.2)
        XCTAssertEqual(recognizer.feed([], time: 2.3)?.gesture.direction, .up)
    }
    func testRejectsDiagonalSmallSlowAndChangingContacts() {
        var r = GestureRecognizer()
        _ = r.feed(points(0.4, 0.4), time: 0); _ = r.feed(points(0.7, 0.7), time: 0.2); XCTAssertNil(r.feed([], time: 0.3))
        _ = r.feed(points(0.4), time: 1); _ = r.feed(points(0.5), time: 1.2); XCTAssertNil(r.feed([], time: 1.4))
        _ = r.feed(points(0.4), time: 2); _ = r.feed(points(0.7), time: 3); XCTAssertNil(r.feed([], time: 3.5))
        _ = r.feed(points(0.7), time: 4); _ = r.feed(points(0.4, count: 4), time: 4.2); XCTAssertNil(r.feed([], time: 4.3))
    }
    func testLiftedFingerDoesNotShiftCentroid() {
        var r = GestureRecognizer()
        _ = r.feed(points(0.4), time: 0); _ = r.feed(points(0.8, count: 2), time: 0.2)
        XCTAssertEqual(r.feed([], time: 0.25)?.gesture.kind, .tap)
    }
    func testInvalidCoordinatesAndClockResetCancel() {
        var r = GestureRecognizer()
        _ = r.feed(points(0.5), time: 1); _ = r.feed(points(.nan), time: 1.1); XCTAssertNil(r.feed([], time: 1.2))
        _ = r.feed(points(0.7), time: 2); _ = r.feed(points(0.4), time: 1); XCTAssertNil(r.feed([], time: 2.3))
    }
    func testMatcherHonorsAppZoneEnabledAndAmbiguity() throws {
        var r = GestureRecognizer()
        _ = r.feed(points(0.2), time: 1); _ = r.feed(points(0.01), time: 1.2)
        let event = try XCTUnwrap(r.feed([], time: 1.3)); let saved = SavedRule(definition: rule(zone: .left))
        XCTAssertEqual(RuleMatcher.match(event, app: "com.google.Chrome", rules: [saved])?.id, saved.id)
        XCTAssertNil(RuleMatcher.match(event, app: "com.apple.Safari", rules: [saved]))
        XCTAssertNil(RuleMatcher.match(event, app: "com.google.Chrome", rules: [SavedRule(enabled: false, definition: rule())]))
        XCTAssertNil(RuleMatcher.match(event, app: "com.google.Chrome", rules: [saved, SavedRule(definition: rule())]))
        XCTAssertNil(RuleMatcher.match(event, app: "com.google.Chrome", rules: [SavedRule(definition: rule(zone: .right))]))
    }
    func testStoreRoundTripAndFailedSavePreservesFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RuleStore(url: dir.appendingPathComponent("rules.json"))
        XCTAssertEqual(try store.load().count, 3)
        let saved = SavedRule(definition: rule()); try store.save([saved]); XCTAssertEqual(try store.load(), [saved])
        XCTAssertThrowsError(try store.save([saved, SavedRule(definition: rule())])); XCTAssertEqual(try store.load(), [saved])
        try Data("broken".utf8).write(to: store.url); XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: store.url), "broken")
    }
    func testSamplesAreValidAndInitiallyDisabled() throws {
        try RuleValidator.validateCollection(Samples.rules); XCTAssertTrue(Samples.rules.allSatisfy { !$0.enabled })
        for saved in Samples.rules { XCTAssertEqual(try RuleValidator.parse(saved.definition.json), saved.definition) }
    }
}
