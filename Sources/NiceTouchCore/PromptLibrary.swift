import Foundation

public enum PromptCategory: String, CaseIterable, Identifiable, Sendable {
    case apps = "Apps", tabs = "Browser tabs", editing = "Editing"
    public var id: String { rawValue }
}
public struct PromptSuggestion: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: PromptCategory
    public let command: String
    public let definition: RuleDefinition
}
public enum PromptLibrary {
    public static let suggestions: [PromptSuggestion] = [
        make("chatgpt-c", "Open ChatGPT with C", .apps, "Open ChatGPT when I draw a C with one finger in all apps.", "*", .drawC, 1, .none, .anywhere, .openChatGPT),
        make("codex-c", "Open Codex with C", .apps, "Open Codex when I draw a C with one finger in all apps.", "*", .drawC, 1, .none, .anywhere, .openCodex),
        make("chatgpt-swipe", "Swipe to ChatGPT", .apps, "When I swipe four fingers left in all apps, open ChatGPT.", "*", .swipe, 4, .left, .anywhere, .openChatGPT),
        make("codex-swipe", "Swipe to Codex", .apps, "When I swipe four fingers right in all apps, open Codex.", "*", .swipe, 4, .right, .anywhere, .openCodex),
        make("previous-tab", "Previous tab in Chrome", .tabs, "When I swipe three fingers left in Chrome, switch to the previous tab.", "com.google.Chrome", .swipe, 3, .left, .anywhere, .previousTab),
        make("next-tab", "Next tab in Chrome", .tabs, "When I swipe three fingers right in Chrome, switch to the next tab.", "com.google.Chrome", .swipe, 3, .right, .anywhere, .nextTab),
        make("reopen-tab", "Reopen a Safari tab", .tabs, "When I tap four fingers in the top zone in Safari, reopen the closed tab.", "com.apple.Safari", .tap, 4, .none, .top, .reopenTab),
        make("close-tab", "Close a Safari tab", .tabs, "When I swipe three fingers down in Safari, close the current tab.", "com.apple.Safari", .swipe, 3, .down, .anywhere, .closeTab),
        make("copy", "Copy in all apps", .editing, "When I swipe four fingers up in all apps, copy.", "*", .swipe, 4, .up, .anywhere, .copy),
        make("paste", "Paste in all apps", .editing, "When I swipe four fingers down in all apps, paste.", "*", .swipe, 4, .down, .anywhere, .paste),
        make("undo", "Undo in Safari", .editing, "When I tap three fingers in Safari, undo.", "com.apple.Safari", .tap, 3, .none, .anywhere, .undo),
        make("redo", "Redo from the bottom edge", .editing, "When I tap four fingers in the bottom zone in Safari, redo.", "com.apple.Safari", .tap, 4, .none, .bottom, .redo)
    ]
    public static func search(_ query: String, category: PromptCategory? = nil) -> [PromptSuggestion] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return suggestions.filter { suggestion in
            (category == nil || suggestion.category == category) && words.allSatisfy { word in
                (suggestion.title + " " + suggestion.command + " " + suggestion.category.rawValue).localizedStandardContains(word)
            }
        }
    }
    private static func make(_ id: String, _ title: String, _ category: PromptCategory, _ command: String,
                             _ app: String, _ kind: GestureKind, _ fingers: Int, _ direction: Direction, _ zone: Zone, _ action: RuleAction) -> PromptSuggestion {
        PromptSuggestion(id: id, title: title, category: category, command: command,
            definition: RuleDefinition(name: action.label, app: app, gesture: Gesture(kind: kind, fingers: fingers, direction: direction, zone: zone), action: action))
    }
}
