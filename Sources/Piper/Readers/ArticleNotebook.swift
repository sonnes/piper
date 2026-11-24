import AppKit
import Captures
import PiperCore
import SwiftUI

/// The Notes tab of a link capture: one page with the summary of the reader,
/// the highlights with their notes, and the questions to the margin agent.
struct ArticleNotebook: View {

    // MARK: - Properties

    @Bindable var model: AppModel
    let note: Note
    let url: URL
    @State private var loader = ArticleLoader()
    @State private var summary = ""
    @State private var pendingSummary: Task<Void, Never>?
    @State private var saving = false

    private var children: [Note] { model.store.children(of: note.id) }
    private var reading: Reading { note.reading ?? Reading() }
    private var host: String { Site(url)?.key ?? url.absoluteString }
    private var title: String { reading.title ?? host }

    /// The highlights that changed after Save as File wrote the file.
    private var changedCount: Int {
        guard let saved = reading.savedAt else { return 0 }
        return ReadingList.highlights(in: children).filter { $0.modifiedAt > saved }.count
    }

    var body: some View {
        let children = children
        let highlights = ReadingList.highlights(in: children)
        let questions = ReadingList.questions(in: children)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(children)
                label("Summary")
                NoteTextEditor(text: Binding(get: { summary }, set: { text in
                    summary = text
                    scheduleSummarySave()
                }), font: PiperTheme.paperUINS(.row))
                .frame(minHeight: Metrics.summaryMinimumHeight)
                .padding(Metrics.fieldPadding)
                .background(PiperTheme.paperTint, in: RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous))
                .accessibilityLabel("Summary")
                HStack(alignment: .firstTextBaseline) {
                    label("Highlights")
                    Spacer()
                    if !highlights.isEmpty {
                        Button("Ask about all of them", action: review)
                            .buttonStyle(.plain)
                            .font(PiperTheme.paperUI(.body, weight: .medium)).foregroundStyle(PiperTheme.brand)
                            .disabled(!loaded)
                            .help("Ask the margin agent what your highlights add up to")
                    }
                }
                if highlights.isEmpty {
                    Text("Select text in the Reader tab and choose a color or Note. On a web page, select text and press Shift twice.")
                        .font(PiperTheme.paperUI(.row)).foregroundStyle(PiperTheme.paperMuted)
                }
                ForEach(highlights) { highlight in
                    HighlightEntry(highlight: highlight) { show(highlight.id) }
                }
                if !questions.isEmpty {
                    label("Questions")
                    ForEach(questions) { question in
                        QuestionEntry(question: question, waiting: model.reader.waitingNotes.contains(question.id),
                                      failure: model.reader.failures[question.id]) { show(question.id) }
                    }
                }
            }
            .frame(maxWidth: Metrics.notebookWidth, alignment: .leading)
            .padding(.horizontal, Metrics.horizontalPadding).padding(.top, Metrics.topPadding)
            .padding(.bottom, TabIslandMetrics.clearance)
            .frame(maxWidth: .infinity)
        }
        .background(PiperTheme.paper)
        .foregroundStyle(PiperTheme.paperInk)
        .onAppear {
            summary = ReadingList.summary(in: children)?.text ?? ""
            do {
                loader.load(url, title: reading.title, pageText: try model.store.pageText(for: url))
            } catch {
                model.messages.report(error)
                loader.load(url, title: reading.title, pageText: nil)
            }
        }
        .onDisappear { saveSummary() }
    }

    // MARK: - Parts

    private func header(_ children: [Note]) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(([host] + [kicker].compactMap { $0 }).joined(separator: " · "))
                    .font(PiperTheme.paperUI(.body))
                    .foregroundStyle(PiperTheme.paperFaint)
                Spacer()
                if let file = reading.savedFile {
                    if changedCount > 0 {
                        Button("Update File (\(changedCount) new)", action: update)
                            .buttonStyle(.plain).font(PiperTheme.paperUI(.body, weight: .medium)).foregroundStyle(PiperTheme.brand)
                            .help(file)
                    } else {
                        Text("Saved to " + URL(fileURLWithPath: file).deletingLastPathComponent().lastPathComponent)
                            .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint).help(file)
                    }
                    IconButton(title: "Show in Finder", icon: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)])
                    }
                } else {
                    IconButton(title: "Save as File", icon: "doc", active: saving) { saving = true }
                        .popover(isPresented: $saving, arrowEdge: .bottom) {
                            SaveArticleForm(model: model, note: note, url: url, title: title) { saving = false }
                        }
                }
            }
            Text(title)
                .font(PiperTheme.paperTitle(.title))
                .textSelection(.enabled)
            HStack(spacing: Metrics.headerLinkSpacing) {
                Button("Open in Reader") { model.articleTabs.choose(.reader, for: note) }
                    .buttonStyle(.plain).fontWeight(.medium).foregroundStyle(PiperTheme.brand)
                Text(ReadingList.counts(of: children)).foregroundStyle(PiperTheme.paperMuted)
            }
            .font(PiperTheme.paperUI(.row))
        }
        .padding(.bottom, Metrics.headerSpacing)
    }

    private var kicker: String? {
        if let finished = reading.finishedAt { return "Finished " + RowTime.text(finished) }
        return reading.minutesLeft.map { "\($0) min left" }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(PiperTheme.paperUI(.body, weight: .medium))
            .foregroundStyle(PiperTheme.paperFaint)
            .padding(.top, Metrics.labelTopPadding).padding(.bottom, Metrics.fieldPadding)
            .accessibilityAddTraits(.isHeader)
    }

    private var loaded: Bool {
        if case .loaded = loader.state { return true }
        return false
    }

    // MARK: - Actions

    private func show(_ id: UUID) {
        model.articleTabs.showHighlight(id, in: note.id)
    }

    private func review() {
        guard case .loaded(let article) = loader.state else { return }
        do { try model.reader.reviewHighlights(in: note.id, article: article) } catch { model.messages.report(error) }
    }

    private func scheduleSummarySave() {
        pendingSummary?.cancel()
        pendingSummary = Task { @MainActor in
            try? await Task.sleep(for: ReaderMetrics.saveDelay)
            guard !Task.isCancelled else { return }
            saveSummary()
        }
    }

    /// Saves the summary as a child note with the tag summary. An empty
    /// summary deletes the note.
    private func saveSummary() {
        pendingSummary?.cancel()
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let existing = ReadingList.summary(in: children) {
                if text.isEmpty {
                    try model.store.delete([existing.id])
                } else if existing.text != summary {
                    try model.store.update(existing.id, text: summary)
                }
            } else if !text.isEmpty {
                try model.store.addChild(summary, to: note.id, tags: [NoteTag.summary.rawValue])
            }
        } catch {
            model.messages.report(error)
        }
    }

    /// Adds the new highlights to the end of the saved file.
    private func update() {
        guard let file = reading.savedFile, let saved = reading.savedAt,
              let addition = ArticleMarkdown.update(children: children, after: saved, date: Date()) else { return }
        do {
            guard FileManager.default.fileExists(atPath: file) else {
                try model.store.updateReading(note.id) { $0.savedFile = nil; $0.savedAt = nil }
                throw PiperError("The saved file is gone. Choose Save as File again.")
            }
            try model.articleActions.append(addition, toFile: file, for: [note])
        } catch { model.messages.report(error) }
    }
}

// MARK: - Entries

/// The Notes tab of a link capture, and its Save as File popover.
extension ArticleNotebook {
    enum Metrics {
        /// The column of the Notes tab.
        static let notebookWidth: CGFloat = 600
        static let horizontalPadding: CGFloat = 56
        static let topPadding: CGFloat = 8
        static let summaryMinimumHeight: CGFloat = 70
        /// The serif of a quote: 17 points, with a line height of 1.55.
        static let quoteFontSize: CGFloat = 17
        static let quoteLineSpacing: CGFloat = 5
        /// The padding and the corner radius of the summary field, a question, and the file preview.
        static let fieldPadding: CGFloat = 10
        static let fieldRadius: CGFloat = 12
        static let labelTopPadding: CGFloat = 22
        static let colorBarWidth: CGFloat = 2
        static let formWidth: CGFloat = 360
        static let formPadding: CGFloat = 14
        static let previewHeight: CGFloat = 140
        static let previewFontSize: CGFloat = 11
        /// The space between the lines of the header, and under it.
        static let headerSpacing: CGFloat = 4
        static let headerLinkSpacing: CGFloat = 12
        /// A highlight: the color bar, then the quote, the note, and the source.
        static let entrySpacing: CGFloat = 16
        static let entryLineSpacing: CGFloat = 6
        static let entryVerticalPadding: CGFloat = 10
        static let commentLineSpacing: CGFloat = 3
        /// A question: its title and its state, on a tinted field.
        static let questionSpacing: CGFloat = 4
        static let questionTitleSpacing: CGFloat = 8
        static let questionPadding = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        /// The rows of Save as File, and the space between a label and its control.
        static let formSpacing: CGFloat = 10
        static let formToggleSpacing: CGFloat = 5
        static let formLabelSpacing: CGFloat = 4
        static let fieldBorder: CGFloat = 1
    }
}

private struct HighlightEntry: View {
    let highlight: Note
    let open: () -> Void

    var body: some View {
        let comment = HighlightText.comment(of: highlight.text, quote: highlight.anchor?.quote)
        Button(action: open) {
            HStack(alignment: .top, spacing: ArticleNotebook.Metrics.entrySpacing) {
                Rectangle().fill(PiperTheme.quoteBar).frame(width: ArticleNotebook.Metrics.colorBarWidth)
                VStack(alignment: .leading, spacing: ArticleNotebook.Metrics.entryLineSpacing) {
                    Text(highlight.anchor?.quote ?? highlight.text.components(separatedBy: "\n\n")[0])
                        .font(PiperTheme.paperSerif(ArticleNotebook.Metrics.quoteFontSize))
                        .foregroundStyle(PiperTheme.paperMuted)
                        .lineSpacing(ArticleNotebook.Metrics.quoteLineSpacing)
                    if !comment.isEmpty {
                        Text(comment).font(PiperTheme.paperUI(.row)).foregroundStyle(PiperTheme.paperInk).lineSpacing(ArticleNotebook.Metrics.commentLineSpacing)
                    }
                    Text(([highlight.sources.first] + [highlight.createdAt.formatted(date: .omitted, time: .shortened)])
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, ArticleNotebook.Metrics.entryVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the highlight in the article")
    }
}

private struct QuestionEntry: View {
    let question: Note
    let waiting: Bool
    let failure: String?
    let open: () -> Void

    var body: some View {
        let thread = NoteThread(question.text)
        let parts = thread.title.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let answers = thread.turns.filter { !$0.answer.isEmpty }.count
        Button(action: open) {
            VStack(alignment: .leading, spacing: ArticleNotebook.Metrics.questionSpacing) {
                HStack(spacing: ArticleNotebook.Metrics.questionTitleSpacing) {
                    Text("✳ " + (parts.first ?? "Ask")).font(PiperTheme.paperUI(.row, weight: .semibold))
                        .foregroundStyle(PiperTheme.claude)
                    Text(parts.count > 1 ? parts[1] : "").font(PiperTheme.paperUI(.row)).lineLimit(1)
                    Spacer(minLength: ArticleNotebook.Metrics.questionTitleSpacing)
                    if waiting {
                        ProgressView().controlSize(.mini)
                    } else if answers > 0 {
                        Text("\(answers) answer" + (answers == 1 ? "" : "s"))
                            .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                    }
                }
                if let failure { Text(failure).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted) }
            }
            .padding(ArticleNotebook.Metrics.questionPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PiperTheme.paperTint, in: RoundedRectangle(cornerRadius: ArticleNotebook.Metrics.fieldRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, ArticleNotebook.Metrics.fieldPadding)
    }
}

// MARK: - Save As File

/// The popover of Save as File: the folder, the parts to include, and the text.
private struct SaveArticleForm: View {

    /// A folder that can take the file: a folder of the Folders index, or a folder inside the open one.
    struct Destination: Hashable {
        let root: String
        let folder: String

        var label: String {
            let name = URL(fileURLWithPath: root).lastPathComponent
            return folder.isEmpty ? name : name + " / " + folder.replacingOccurrences(of: "/", with: " / ")
        }
    }

    @Bindable var model: AppModel
    let note: Note
    let url: URL
    let title: String
    let close: () -> Void
    @AppStorage(AppDefaults.Key.articleExportFolder) private var lastFolder = ""
    @State private var destination: Destination?
    @State private var parts = ArticleMarkdown.Parts()

    private var destinations: [Destination] {
        model.library.wikiPaths.flatMap { root -> [Destination] in
            let active = root == model.library.wikiPath
            return [Destination(root: root, folder: "")] + (active ? model.library.folders.map { Destination(root: root, folder: $0) } : [])
        }
    }

    private var text: String {
        ArticleMarkdown.file(title: title, url: url, children: model.store.children(of: note.id), parts: parts, date: Date())
    }

    private var fileName: String { ArticleMarkdown.fileName(for: title) }

    var body: some View {
        VStack(alignment: .leading, spacing: ArticleNotebook.Metrics.formSpacing) {
            Text("Save as File").font(PiperTheme.paperUI(.body, weight: .semibold))
            field("Folder") {
                Picker("Folder", selection: $destination) {
                    ForEach(destinations, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
                .labelsHidden()
            }
            field("Include") {
                VStack(alignment: .leading, spacing: ArticleNotebook.Metrics.formToggleSpacing) {
                    Toggle("Highlights and your notes", isOn: $parts.highlights)
                    Toggle("Summary", isOn: $parts.summary)
                    Toggle("Agent answers", isOn: $parts.answers)
                }
                .toggleStyle(.checkbox)
            }
            ScrollView {
                Text(text)
                    .font(Font(PiperTheme.manuscript(size: ArticleNotebook.Metrics.previewFontSize)))
                    .foregroundStyle(PiperTheme.paperMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: ArticleNotebook.Metrics.previewHeight)
            .padding(ArticleNotebook.Metrics.fieldPadding)
            .background(PiperTheme.paper, in: RoundedRectangle(cornerRadius: ArticleNotebook.Metrics.fieldRadius))
            .overlay(RoundedRectangle(cornerRadius: ArticleNotebook.Metrics.fieldRadius).strokeBorder(PiperTheme.paperRule, lineWidth: ArticleNotebook.Metrics.fieldBorder))
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save \(fileName)", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(destination == nil)
            }
        }
        .padding(ArticleNotebook.Metrics.formPadding)
        .frame(width: ArticleNotebook.Metrics.formWidth)
        .onAppear {
            destination = destinations.first { $0.label == lastFolder } ?? destinations.first
        }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: ArticleNotebook.Metrics.formLabelSpacing) {
            Text(label).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
            content()
        }
    }

    /// Writes a new file. A file with the same name stays, and the new file
    /// gets a number.
    private func save() {
        guard let destination else { return }
        do {
            try model.articleActions.saveAsFile(text, named: fileName, root: destination.root, folder: destination.folder, for: [note])
            model.messages.show("Saved to " + destination.label)
            lastFolder = destination.label
            close()
        } catch { model.messages.report(error) }
    }
}
