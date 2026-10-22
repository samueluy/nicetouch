import SwiftUI
import NiceTouchCore

struct PromptLibraryView: View {
    let isBusy: Bool
    let use: (PromptSuggestion) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: PromptCategory?
    private var suggestions: [PromptSuggestion] { PromptLibrary.search(query, category: category) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Prompt library").font(.title2.weight(.medium))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Choose a suggestion, edit the command, then create a preview. Hold Fn while performing gestures.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Search suggestions", text: $query).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search prompt library")
            Picker("Category", selection: $category) {
                Text("All").tag(Optional<PromptCategory>.none)
                ForEach(PromptCategory.allCases) { Text($0.rawValue).tag(Optional($0)) }
            }.pickerStyle(.segmented)
            ScrollView {
                if suggestions.isEmpty {
                    VStack(spacing: 8) {
                        Text("No suggestions found").font(.headline)
                        Text("Try an app name, action or gesture.").foregroundStyle(.secondary)
                        Button("Clear filters") { query = ""; category = nil }
                    }.frame(maxWidth: .infinity).padding(.vertical, 50)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        ForEach(suggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 12) {
                                Label(suggestion.title, systemImage: suggestion.definition.gesture.symbol).font(.headline)
                                Text(suggestion.command).font(.callout).textSelection(.enabled)
                                Text(suggestion.definition.gesture.label + " · " + suggestion.definition.appLabel)
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Button("Use prompt") { use(suggestion); dismiss() }
                                    .disabled(isBusy).accessibilityLabel("Use prompt: " + suggestion.title)
                            }.padding(16).frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            Text("ChatGPT and Codex need their macOS apps installed. Suggestions can overlap; preview checks conflicts before saving. Draw C with its opening on the right, then lift your finger.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 740, height: 650)
    }
}
