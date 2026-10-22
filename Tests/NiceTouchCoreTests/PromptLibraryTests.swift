import XCTest
@testable import NiceTouchCore

final class PromptLibraryTests: XCTestCase {
    func testEverySuggestionIsValidAndGroundedInItsCommand() throws {
        XCTAssertEqual(Set(PromptLibrary.suggestions.map(\.id)).count, PromptLibrary.suggestions.count)
        for suggestion in PromptLibrary.suggestions {
            XCTAssertNoThrow(try RuleValidator.parse(suggestion.definition.json), suggestion.id)
            XCTAssertNil(CommandIntentValidator.clarification(for: suggestion.command), suggestion.id)
            XCTAssertNoThrow(try CommandIntentValidator.validate(suggestion.definition, command: suggestion.command), suggestion.id)
        }
    }
    func testSearchCombinesWordsAndCategory() {
        XCTAssertEqual(PromptLibrary.search("CHATGPT").count, 2)
        XCTAssertEqual(PromptLibrary.search("chrome previous").map(\.id), ["previous-tab"])
        XCTAssertEqual(PromptLibrary.search("copy", category: .tabs).count, 0)
        XCTAssertEqual(PromptLibrary.search("", category: .apps).count, 4)
        XCTAssertTrue(PromptLibrary.search("unavailable suggestion").isEmpty)
    }
    func testSameCTriggerForDifferentLaunchActionsConflicts() {
        let a = PromptLibrary.suggestions[0].definition, b = PromptLibrary.suggestions[1].definition
        XCTAssertEqual(RuleValidator.conflicts(b, with: [SavedRule(definition: a)]).count, 1)
    }
    func testExactUserExampleAndSpecificSourceApp() throws {
        let chat = PromptLibrary.suggestions[0].definition
        XCTAssertNoThrow(try CommandIntentValidator.validate(chat, command: "Open ChatGPT when I draw a C"))
        var scoped = chat; scoped.app = "com.apple.Safari"
        XCTAssertNoThrow(try CommandIntentValidator.validate(scoped, command: "In Safari, open ChatGPT when I draw a C"))
        XCTAssertThrowsError(try CommandIntentValidator.validate(chat, command: "In Safari, open ChatGPT when I draw a C"))
        XCTAssertThrowsError(try CommandIntentValidator.validate(chat, command: "Open Codex when I draw a C"))
        XCTAssertThrowsError(try CommandIntentValidator.validate(chat, command: "In CustomEditor, open ChatGPT when I draw a C"))
    }
    func testUnsupportedDrawingOrAmbiguousTargetRequiresClarification() {
        for command in ["Open ChatGPT when I draw an X", "Open ChatGPT and Codex when I draw a C", "Open ChatGPT when I draw a C with three fingers", "Open ChatGPT when I draw a C with two fingers", "Open ChatGPT when I draw a C with 10 fingers"] {
            XCTAssertNotNil(CommandIntentValidator.clarification(for: command), command)
        }
    }
    func testNewRuleConstraintsAndOldRulesRemainValid() {
        var drawing = PromptLibrary.suggestions[0].definition
        drawing.gesture.fingers = 3; XCTAssertThrowsError(try RuleValidator.validate(drawing))
        drawing.gesture.fingers = 1; drawing.gesture.direction = .left
        XCTAssertThrowsError(try RuleValidator.validate(drawing))
        var swipe = Samples.rules[0].definition; swipe.gesture.fingers = 1
        XCTAssertThrowsError(try RuleValidator.validate(swipe))
        for sample in Samples.rules { XCTAssertNoThrow(try RuleValidator.parse(sample.definition.json)) }
    }
    func testLaunchTargetsAreFixedAndKeyboardActionsHaveNone() {
        XCTAssertEqual(RuleAction.openChatGPT.launchBundleIdentifier, "com.openai.chat")
        XCTAssertEqual(RuleAction.openCodex.launchBundleIdentifier, "com.openai.codex")
        for action in [RuleAction.copy, .paste, .previousTab, .closeTab] { XCTAssertNil(action.launchBundleIdentifier) }
    }
}
