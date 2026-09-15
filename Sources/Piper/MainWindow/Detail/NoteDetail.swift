import AppKit
import Captures
import SwiftUI

/// The Inbox reader shows captured text or the selected web page.
struct NoteDetail: View {

    // MARK: Properties

    @Bindable var model: AppModel
    let note: Note
    @State private var links = CaptureLinks("")
    @State private var selectedURL: URL?

    private var date: String {
        note.modifiedAt.formatted(date: .long, time: .shortened)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppDefaults.Reader.horizontalInset)
                .padding(.top, AppDefaults.Reader.topInset)
            if let selectedURL {
                NoteWebReader(url: selectedURL, showNote: { self.selectedURL = nil }) { text, title, url in
                    model.store.add(text, source: title, sourceURL: url.absoluteString,
                                    to: "Inbox", interpretSection: false)
                }
            } else {
                ScrollView {
                    Text(links.text)
                        .font(PiperTheme.ui(18))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(maxWidth: AppDefaults.Reader.columnWidth, alignment: .leading)
                        .padding(.horizontal, AppDefaults.Reader.horizontalInset)
                        .padding(.top, 20)
                        .padding(.bottom, 64)
                        .frame(maxWidth: .infinity)
                }
            }
            if !note.sources.isEmpty || !sourceURLs.isEmpty { sources }
        }
        .background(PiperTheme.page)
        .onChange(of: note.text, initial: true) {
            links = CaptureLinks(note.text)
            selectedURL = links.standaloneURL
        }
        .environment(\.openURL, OpenURLAction { url in
            guard CaptureLinks.isWebURL(url) else { return .discarded }
            selectedURL = url
            return .handled
        })
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.section)
                        .font(PiperTheme.ui(13, weight: .bold))
                        .foregroundStyle(PiperTheme.secondary)
                    Text(date)
                        .font(PiperTheme.ui(12))
                        .foregroundStyle(PiperTheme.secondary)
                }
                Spacer(minLength: 12)
                Button(note.isDone ? "Reopen" : "Mark as Done") { model.store.toggleDone(note.id) }
                    .buttonStyle(PiperButtonStyle())
                Button("Edit") { model.openNoteEditor?(note) }
                    .buttonStyle(PiperButtonStyle(prominent: true))
            }
            .frame(minHeight: AppDefaults.Reader.headerHeight)
            Rule()
        }
    }

    private var sources: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 8) {
                Text(note.sources.joined(separator: " · "))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if sourceURLs.count > 1 {
                    Menu("Open Source") {
                        ForEach(sourceURLs, id: \.self) { url in
                            Button(url.absoluteString) { selectedURL = url }
                        }
                    }
                    .fixedSize()
                } else if let url = sourceURLs.first {
                    Button("Open Source") { selectedURL = url }
                        .buttonStyle(.plain)
                        .foregroundStyle(PiperTheme.accent)
                }
            }
            .font(PiperTheme.ui(11))
            .foregroundStyle(PiperTheme.secondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(PiperTheme.statusBar)
        }
    }

    private var sourceURLs: [URL] {
        note.sourceURLs.compactMap(URL.init(string:)).filter(CaptureLinks.isWebURL)
    }
}
