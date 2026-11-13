import AppKit
import Feeds
import SwiftUI
import UniformTypeIdentifiers

/// Adds a feed from the address of a site or a feed, or every feed of an OPML file.
struct AddFeedSheet: View {
    let feeds: FeedStore
    /// Closes the sheet. A new feed is the argument, if one was added.
    let done: (String?) -> Void

    @State private var address = ""
    @State private var found: [FeedDiscovery.Found] = []
    @State private var chosen: String?
    @State private var searching = false
    @State private var message: String?
    @State private var search: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Feed").font(PiperTheme.ui(.title, weight: .semibold))
            TextField("Site or feed address", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit(find)
                .onChange(of: address) { _, _ in
                    found = []
                    chosen = nil
                    message = nil
                }
            if searching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for feeds…").foregroundStyle(PiperTheme.secondary)
                }
                .font(PiperTheme.ui(.secondary))
            }
            if !found.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(found) { feed in
                        Button { chosen = feed.url } label: {
                            HStack(spacing: 8) {
                                Image(systemName: chosen == feed.url ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(chosen == feed.url ? PiperTheme.accent : PiperTheme.faint)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(feed.title ?? feed.url).lineLimit(1)
                                    Text(feed.url).font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 8)
                                Text(detail(feed)).font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(feeds.feed(feed.url) != nil)
                    }
                }
            }
            if let message {
                Text(message).font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Menu("Import") {
                    Button("Import from NetNewsWire") { importFile(OPMLImport.netNewsWireFile) }
                    Button("Import OPML File…", action: chooseFile)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Button("Close") { done(nil) }.keyboardShortcut(.cancelAction)
                if found.isEmpty {
                    Button("Find Feeds", action: find)
                        .keyboardShortcut(.defaultAction)
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                } else {
                    Button("Subscribe", action: subscribe)
                        .keyboardShortcut(.defaultAction)
                        .disabled(chosen == nil)
                }
            }
        }
        .font(PiperTheme.ui(.body))
        .padding(20)
        .frame(width: AppDefaults.Feeds.addSheetWidth)
        .onDisappear { search?.cancel() }
    }

    private func detail(_ feed: FeedDiscovery.Found) -> String {
        if feeds.feed(feed.url) != nil { return "Subscribed" }
        return [feed.format, feed.articles.map { "\($0) articles" }].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Actions

    private func find() {
        let text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !searching else { return }
        searching = true
        message = nil
        search = Task {
            do {
                let results = try await FeedDiscovery.find(text)
                guard !Task.isCancelled else { return }
                found = results
                chosen = results.first { feeds.feed($0.url) == nil }?.url
                if results.isEmpty { message = "Piper found no feed at this address." }
            } catch {
                message = error.localizedDescription
            }
            searching = false
        }
    }

    private func subscribe() {
        guard let feed = found.first(where: { $0.url == chosen }) else { return }
        feeds.subscribe(url: feed.url, title: feed.title)
        done(feed.url)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "opml") ?? .xml, .xml]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(url)
    }

    private func importFile(_ url: URL) {
        do {
            let specifiers = try OPMLImport.feeds(in: url)
            let added = feeds.subscribe(specifiers)
            message = added == 0 ? "Piper already has every feed of \(url.lastPathComponent)."
                : "Added \(added) \(added == 1 ? "feed" : "feeds") from \(url.lastPathComponent)."
        } catch {
            message = error.localizedDescription
        }
    }
}
