import AppKit
import Briefs
import SwiftUI

/// The Brief pane of Settings: the sources, the blocked sites, and morning builds.
struct BriefSettings: View {
    @Bindable var brief: BriefBuilder

    @State private var blockedText = ""

    private static let privacySettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    var body: some View {
        Form {
            Section {
                ForEach(brief.sources) { source in
                    if source.needsAccess {
                        LabeledContent(title(of: source)) {
                            Button("Open Privacy Settings") {
                                if let url = URL(string: Self.privacySettings) { NSWorkspace.shared.open(url) }
                            }
                        }
                    } else {
                        Toggle(title(of: source), isOn: Binding(
                            get: { !brief.disabledSources.contains(source.id) },
                            set: { isOn in
                                if isOn { brief.disabledSources.remove(source.id) } else { brief.disabledSources.insert(source.id) }
                            }))
                    }
                }
                Toggle(HackerNews.name, isOn: Binding(
                    get: { !brief.disabledSources.contains(HackerNews.sourceID) },
                    set: { isOn in
                        if isOn { brief.disabledSources.remove(HackerNews.sourceID) } else { brief.disabledSources.insert(HackerNews.sourceID) }
                    }))
                Button("Check Again") { brief.refreshSources() }
            } header: {
                Text("Sources")
            } footer: {
                Text("A source with Open Privacy Settings needs Full Disk Access. Agent sessions that Piper starts can get the same access.")
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
            }
            Section {
                TextEditor(text: $blockedText)
                    .font(PiperTheme.ui(12))
                    .frame(height: 130)
                    .onChange(of: blockedText) { _, text in
                        brief.blockedSites = BlockedSites.normalized(text.components(separatedBy: .newlines))
                    }
            } header: {
                Text("Blocked Sites")
            } footer: {
                Text("Enter one host on each line. A block also covers each subdomain. Piper always blocks private addresses.")
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
            }
            Section {
                Toggle("Build a brief each morning", isOn: $brief.morningBuilds)
            } footer: {
                Text("Piper tries one time each day, between 5:00 and noon, while it is open.")
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            blockedText = brief.blockedSites.joined(separator: "\n")
            brief.refreshSources()
        }
    }

    private func title(of source: BriefSource) -> String {
        source.profile.map { "\(source.name) · \($0)" } ?? source.name
    }
}
