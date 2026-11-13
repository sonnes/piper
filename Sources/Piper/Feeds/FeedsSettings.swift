import AppKit
import History
import SwiftUI

/// The Feeds pane of Settings: the history sources and the blocked sites of Discover.
struct FeedsSettings: View {
    @Bindable var discover: DiscoverScan

    @State private var blockedText = ""

    private static let privacySettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    var body: some View {
        Form {
            Section {
                if discover.sources.isEmpty {
                    Text("Piper found no browser history on this Mac.")
                        .foregroundStyle(PiperTheme.secondary)
                }
                ForEach(discover.sources) { source in
                    if source.needsAccess {
                        LabeledContent(title(of: source)) {
                            Button("Open Privacy Settings") {
                                if let url = URL(string: Self.privacySettings) { NSWorkspace.shared.open(url) }
                            }
                        }
                    } else {
                        Toggle(title(of: source), isOn: Binding(
                            get: { !discover.disabledSources.contains(source.id) },
                            set: { isOn in
                                if isOn { discover.disabledSources.remove(source.id) } else { discover.disabledSources.insert(source.id) }
                            }))
                    }
                }
                Button("Check Again") { discover.refreshSources() }
            } header: {
                Text("History for Discover")
            } footer: {
                Text("Discover reads the last \(HistoryDigest.days) days of history on this Mac. The history does not leave your Mac. A source with Open Privacy Settings needs Full Disk Access. Agent sessions that Piper starts can get the same access.")
                    .font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.secondary)
            }
            Section {
                TextEditor(text: $blockedText)
                    .font(PiperTheme.ui(.secondary))
                    .frame(height: 130)
                    .onChange(of: blockedText) { _, text in
                        discover.blockedSites = BlockedSites.normalized(text.components(separatedBy: .newlines))
                    }
            } header: {
                Text("Blocked Sites")
            } footer: {
                Text("Enter one host on each line. A block also covers each subdomain. Piper always blocks private addresses.")
                    .font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            blockedText = discover.blockedSites.joined(separator: "\n")
            discover.refreshSources()
        }
    }

    private func title(of source: HistorySource) -> String {
        source.profile.map { "\(source.name) · \($0)" } ?? source.name
    }
}
