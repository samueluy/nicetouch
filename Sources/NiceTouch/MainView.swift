import SwiftUI
import NiceTouchCore
import NiceTouchModels

private let ink = Color.primary
private let accent = Color(red: 0.20, green: 0.43, blue: 0.34)

struct MainView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var models: ModelProviderController
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().opacity(0.5)
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            Text("TRACKPAD").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                            Spacer()
                            Label("Built-in trackpad", systemImage: "laptopcomputer").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        TrackpadView(rule: state.selectedRule, preview: state.draft != nil, enabled: state.draft != nil || state.rules.first(where: { $0.id == state.selected })?.enabled == true)
                            .frame(maxWidth: .infinity).frame(height: 240)
                        HStack(spacing: 7) {
                            Circle().fill(state.engineRunning ? accent : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                            Text(state.lastEvent).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            Spacer()
                            Text(state.requireFn ? "HOLD FN TO USE" : "GESTURES RUN LOCALLY").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.tertiary)
                        }
                        composer
                    }.frame(maxWidth: .infinity)
                    inspector.frame(width: 252)
                }.padding(28)
                if !state.warning.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(state.warning).font(.system(size: 12)).textSelection(.enabled)
                        Spacer()
                        Button { state.warning = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss warning")
                    }.padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 28).padding(.bottom, 12)
                }
                Spacer(minLength: 0)
                Divider().opacity(0.5)
                HStack {
                    Label(models.statusLabel, systemImage: models.selection == .api ? "network" : "cpu").font(.system(size: 11)).foregroundStyle(.secondary)
                    if state.busy || models.busy { ProgressView().controlSize(.mini) }
                    Spacer()
                    Button("Model settings") { state.showModel = true }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                }.padding(.horizontal, 28).padding(.vertical, 15)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.foregroundStyle(ink).tint(accent)
        .sheet(isPresented: $state.showModel) { modelSettings }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "hand.draw.fill").font(.system(size: 22)).foregroundStyle(accent)
                Text("NiceTouch").font(.system(size: 19, weight: .semibold, design: .rounded))
            }.padding(.top, 43).padding(.horizontal, 22)
            HStack {
                Text("GESTURES").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.6)
                Spacer()
                Text("\(state.rules.count)").font(.system(size: 10, design: .monospaced))
            }.foregroundStyle(.secondary).padding(.horizontal, 22).padding(.top, 36).padding(.bottom, 13)
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(state.rules) { rule in
                        Button { state.selected = rule.id; state.discardPreview() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: rule.definition.gesture.symbol).font(.system(size: 15)).frame(width: 22)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(rule.definition.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(rule.definition.appLabel + (rule.enabled ? "" : " · Off")).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if rule.enabled { Circle().fill(accent).frame(width: 5, height: 5) }
                            }.padding(12).contentShape(Rectangle())
                                .background(state.selected == rule.id && state.draft == nil ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 10)
            }
            Button { state.selected = nil; state.discardPreview() } label: { Label("New gesture", systemImage: "plus").font(.system(size: 12)) }.buttonStyle(.plain).foregroundStyle(accent).padding(22)
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                Button("Open rules folder", action: state.openRulesFolder).buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(22)
        }.frame(width: 216).background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Gestures").font(.system(size: 27, weight: .medium, design: .rounded)).tracking(-0.6)
            }
            Spacer()
            Button { if state.engineRunning { state.stopEngine() } else { state.startEngine() } } label: {
                Label(state.engineRunning ? "Pause gestures" : "Start gestures", systemImage: state.engineRunning ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .medium))
            }.controlSize(.large)
        }.padding(.horizontal, 28).padding(.top, 37).padding(.bottom, 26)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text("New gesture").font(.system(size: 16, weight: .medium)); Spacer(); Image(systemName: "sparkle").foregroundStyle(accent) }
            Text("Enter the gesture, app and action, then review the rule.").font(.system(size: 11)).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if state.command.isEmpty { Text("When I swipe three fingers left in Chrome, switch to the previous tab.").font(.system(size: 13)).foregroundStyle(.tertiary).padding(12).allowsHitTesting(false) }
                TextEditor(text: $state.command).font(.system(size: 13)).scrollContentBackground(.hidden).padding(7).opacity(state.command.isEmpty ? 0.65 : 1).accessibilityLabel("Describe a gesture")
            }.frame(height: 91).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.09)))
            HStack {
                if !models.status.canGenerate { Button("Model settings") { state.showModel = true }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent) }
                else { Label(models.privacyLabel, systemImage: models.selection == .api ? "network" : "lock").font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
                Button(action: state.generate) { Text(state.busy ? "Generating…" : "Create preview").padding(.horizontal, 5) }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!models.status.canGenerate || models.busy || state.busy || state.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 17))
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(state.draft == nil ? "GESTURE DETAILS" : "RULE PREVIEW").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
            if let rule = state.selectedRule {
                Image(systemName: rule.gesture.symbol).font(.system(size: 25, weight: .light)).foregroundStyle(accent).frame(height: 40)
                Text(rule.name).font(.system(size: 21, weight: .medium, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                detail("Gesture", rule.gesture.label)
                detail("In", rule.appLabel)
                detail("Zone", rule.gesture.zone.rawValue.capitalized)
                detail("Action", rule.action.label)
                Divider()
                DisclosureGroup("Structured rule") {
                    ScrollView([.horizontal, .vertical]) { Text(rule.json).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).padding(.vertical, 9) }.frame(height: 175)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                if state.draft != nil {
                    Label(state.conflicts.isEmpty ? "Schema valid · No conflicts" : "Conflict found", systemImage: state.conflicts.isEmpty ? "checkmark.circle" : "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(state.conflicts.isEmpty ? accent : .orange)
                    Button("Save gesture", action: state.saveDraft).buttonStyle(.borderedProminent).controlSize(.large).disabled(!state.conflicts.isEmpty || state.busy)
                    Button("Discard preview", action: state.discardPreview).buttonStyle(.plain).font(.system(size: 11))
                } else if let saved = state.rules.first(where: { $0.id == state.selected }) {
                    Toggle("Enabled", isOn: Binding(get: { saved.enabled }, set: { _ in state.toggle(saved) })).toggleStyle(.switch).font(.system(size: 12))
                    Button("Delete gesture", role: .destructive) { state.delete(saved.id) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                Text("No gesture selected").font(.system(size: 20, weight: .medium, design: .rounded)).padding(.top, 20)
                Text("Select a saved gesture or enter a command.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }
            if state.draft == nil && !state.rawJSON.isEmpty {
                DisclosureGroup("Model output needs repair") { ScrollView { Text(state.rawJSON).font(.system(size: 10, design: .monospaced)).textSelection(.enabled) }.frame(height: 150) }.font(.system(size: 11))
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 17))
    }
    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(title).foregroundStyle(.secondary).frame(width: 48, alignment: .leading); Text(value).textSelection(.enabled); Spacer(minLength: 0) }.font(.system(size: 11))
    }
    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings").font(.system(size: 24, weight: .medium, design: .rounded))
                Spacer()
                Button("Done") { state.showModel = false }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ModelProviderSettingsView(controller: models).disabled(state.busy)
                    Divider()
                    Toggle("Require Fn key for gestures", isOn: $state.requireFn)
                    Text("Hold Fn before touching the trackpad and keep it held until the gesture ends.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Gesture engine").font(.headline)
                    Text("The experimental engine uses Apple's private trackpad API. Disable overlapping macOS gestures in System Settings → Trackpad. Samples start disabled.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Button("Grant Accessibility access", action: state.requestAccessibility)
                    Text("Keyboard actions use standard Mac shortcuts. An app may interpret a shortcut differently.").font(.system(size: 11)).foregroundStyle(.secondary)
                    if !state.warning.isEmpty { Text(state.warning).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
                }.padding(.vertical, 4)
            }
        }.padding(26).frame(width: 620, height: 680)
    }
}

struct TrackpadView: View {
    let rule: RuleDefinition?
    let preview: Bool
    let enabled: Bool
    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width - 8, 480.0)
            ZStack {
                RoundedRectangle(cornerRadius: 23).fill(LinearGradient(colors: [Color(nsColor: .controlBackgroundColor), Color.gray.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.05), radius: 14, y: 12)
                RoundedRectangle(cornerRadius: 23).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.6), lineWidth: 1).padding(3)
                if let rule {
                    zone(rule.gesture.zone)
                    VStack(spacing: 17) {
                        HStack(spacing: 10) {
                            ForEach(0..<rule.gesture.fingers, id: \.self) { _ in
                                Capsule().fill(accent.opacity(enabled ? 0.19 : 0.08)).frame(width: 23, height: 43)
                                    .overlay(Capsule().strokeBorder(accent.opacity(enabled ? 0.35 : 0.15)))
                            }
                        }
                        Image(systemName: rule.gesture.symbol).font(.system(size: 25, weight: .ultraLight)).foregroundStyle(accent.opacity(enabled ? 0.9 : 0.4))
                        Text(rule.gesture.label.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.8).foregroundStyle(.secondary)
                    }
                    VStack { Spacer(); HStack { Text(rule.gesture.zone == .anywhere ? "FULL SURFACE" : rule.gesture.zone.rawValue.uppercased() + " EDGE"); Spacer(); Text(preview ? "PREVIEW" : enabled ? "MAPPED" : "DISABLED") }.font(.system(size: 8, design: .monospaced)).tracking(1).foregroundStyle(.tertiary).padding(18) }
                } else {
                    VStack(spacing: 15) { Image(systemName: "hand.draw").font(.system(size: 35, weight: .ultraLight)); Text("Select a gesture").font(.system(size: 11)) }.foregroundStyle(.tertiary)
                }
            }.frame(width: width, height: 235).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityElement(children: .ignore).accessibilityLabel(rule.map { "Trackpad: \($0.gesture.label), \($0.gesture.zone.rawValue) zone, \(preview ? "preview" : enabled ? "mapped" : "disabled")" } ?? "Trackpad: no gesture selected")
    }
    @ViewBuilder private func zone(_ z: Zone) -> some View {
        GeometryReader { p in
            let w = p.size.width, h = p.size.height
            let rect: CGRect = {
                switch z {
                case .anywhere: return CGRect(x: 0, y: 0, width: w, height: h)
                case .left: return CGRect(x: 0, y: 0, width: w * 0.25, height: h)
                case .right: return CGRect(x: w * 0.75, y: 0, width: w * 0.25, height: h)
                case .top: return CGRect(x: 0, y: 0, width: w, height: h * 0.25)
                case .bottom: return CGRect(x: 0, y: h * 0.75, width: w, height: h * 0.25)
                }
            }()
            Rectangle().fill(accent.opacity(enabled ? 0.045 : 0.015)).frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        }.clipShape(RoundedRectangle(cornerRadius: 23))
    }
}
