import AppKit
import Captures
import PiperCore
import SwiftUI
import Vault

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
    private var metrics: AppDefaults.Notebook.Type { AppDefaults.Notebook.self }
    private var host: String { ArticleBadge.host(url) }
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
                }), font: PiperTheme.uiNS(metrics.summaryFontSize))
                .frame(minHeight: metrics.summaryMinimumHeight)
                .padding(metrics.fieldPadding)
                .background(PiperTheme.page, in: RoundedRectangle(cornerRadius: metrics.fieldRadius))
                .overlay(RoundedRectangle(cornerRadius: metrics.fieldRadius).strokeBorder(PiperTheme.rule, lineWidth: 1))
                .accessibilityLabel("Summary")
                HStack(alignment: .firstTextBaseline) {
                    label("Highlights")
                    Spacer()
                    if !highlights.isEmpty {
                        Button("Ask about all of them", action: review)
                            .buttonStyle(.text)
                            .disabled(!loaded)
                            .help("Ask the margin agent what your highlights add up to")
                    }
                }
                if highlights.isEmpty {
                    Text("Select text in the Reader tab and choose a color or Note. On a web page, select text and press Shift twice.")
                        .font(PiperTheme.ui(12.5)).foregroundStyle(PiperTheme.secondary)
                }
                ForEach(highlights) { highlight in
                    HighlightEntry(highlight: highlight) { show(highlight.id) }
                    Rule()
                }
                if !questions.isEmpty {
                    label("Questions")
                    ForEach(questions) { question in
                        QuestionEntry(question: question, waiting: model.reader.waitingNotes.contains(question.id),
                                      failure: model.reader.failures[question.id]) { show(question.id) }
                    }
                }
            }
            .frame(maxWidth: AppDefaults.Reading.notebookWidth, alignment: .leading)
            .padding(.horizontal, metrics.horizontalPadding).padding(.top, metrics.topPadding)
            .padding(.bottom, AppDefaults.TabIsland.clearance)
            .frame(maxWidth: .infinity)
        }
        .background(PiperTheme.reader)
        .onAppear {
            summary = ReadingList.summary(in: children)?.text ?? ""
            loader.load(url, title: reading.title, pageText: model.store.pageText(for: url))
        }
        .onDisappear { saveSummary() }
    }

    // MARK: - Parts

    private func header(_ children: [Note]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(([host] + [kicker].compactMap { $0 }).joined(separator: " · ").uppercased())
                    .font(PiperTheme.ui(11, weight: .semibold)).tracking(0.4)
                    .foregroundStyle(PiperTheme.faint)
                Spacer()
                if let file = reading.savedFile {
                    if changedCount > 0 {
                        Button("Update File (\(changedCount) new)", action: update).buttonStyle(.text).help(file)
                    } else {
                        Text("Saved to " + URL(fileURLWithPath: file).deletingLastPathComponent().lastPathComponent)
                            .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.faint).help(file)
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
                .font(.system(size: metrics.titleFontSize, weight: .semibold, design: .serif))
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Button("Open in Reader") { model.articleTab = .reader }.buttonStyle(.text)
                Text(ReadingList.counts(of: children)).font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    private var kicker: String? {
        if let finished = reading.finishedAt { return "Finished " + RowTime.text(finished) }
        return reading.minutesLeft.map { "\($0) min left" }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(PiperTheme.ui(11, weight: .semibold)).tracking(0.4)
            .foregroundStyle(PiperTheme.faint)
            .padding(.top, metrics.labelTopPadding).padding(.bottom, metrics.fieldPadding)
            .accessibilityAddTraits(.isHeader)
    }

    private var loaded: Bool {
        if case .loaded = loader.state { return true }
        return false
    }

    // MARK: - Actions

    private func show(_ id: UUID) {
        model.articleTab = .reader
        model.readerScroll = ReaderScroll(note: id, in: note.id)
    }

    private func review() {
        guard case .loaded(let article) = loader.state else { return }
        model.reader.reviewHighlights(in: note.id, article: article)
    }

    private func scheduleSummarySave() {
        pendingSummary?.cancel()
        pendingSummary = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            saveSummary()
        }
    }

    /// Saves the summary as a child note with the tag summary. An empty
    /// summary deletes the note.
    private func saveSummary() {
        pendingSummary?.cancel()
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = ReadingList.summary(in: children) {
            if text.isEmpty {
                model.store.delete(existing.id)
            } else if existing.text != summary {
                model.store.update(existing.id, text: summary)
            }
        } else if !text.isEmpty {
            model.store.addChild(summary, to: note.id, tags: [ReaderAssistant.summaryTag])
        }
    }

    /// Adds the new highlights to the end of the saved file.
    private func update() {
        guard let file = reading.savedFile, let saved = reading.savedAt,
              let addition = ArticleMarkdown.update(children: children, after: saved, date: Date()) else { return }
        do {
            let url = URL(fileURLWithPath: file)
            guard FileManager.default.fileExists(atPath: file) else {
                model.store.updateReading(note.id) { $0.savedFile = nil; $0.savedAt = nil }
                throw PiperError("The saved file is gone. Choose Save as File again.")
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            try Data((text.hasSuffix("\n") ? text : text + "\n").appending(addition).utf8).write(to: url, options: .atomic)
            model.store.updateReading(note.id) { $0.savedAt = Date() }
            model.reload()
        } catch { model.store.report(error) }
    }
}

// MARK: - Entries

private struct HighlightEntry: View {
    let highlight: Note
    let open: () -> Void

    private var color: Color {
        highlight.tags.lazy.compactMap(TagChip.markColor).first ?? PiperTheme.markYellow
    }

    var body: some View {
        let comment = HighlightText.comment(of: highlight.text, quote: highlight.anchor?.quote)
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: AppDefaults.Notebook.colorBarWidth)
                VStack(alignment: .leading, spacing: 6) {
                    Text(highlight.anchor?.quote ?? highlight.text.components(separatedBy: "\n\n")[0])
                        .font(.system(size: AppDefaults.Notebook.quoteFontSize, design: .serif))
                        .lineSpacing(2)
                    if !comment.isEmpty {
                        Text(comment).font(PiperTheme.ui(13)).lineSpacing(1.5)
                    }
                    Text(([highlight.sources.first] + [highlight.createdAt.formatted(date: .omitted, time: .shortened)])
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("✳ " + (parts.first ?? "Ask")).font(PiperTheme.ui(12.5, weight: .semibold))
                        .foregroundStyle(PiperTheme.claude)
                    Text(parts.count > 1 ? parts[1] : "").font(PiperTheme.ui(12.5)).lineLimit(1)
                    Spacer(minLength: 8)
                    if waiting {
                        ProgressView().controlSize(.mini)
                    } else if answers > 0 {
                        Text("\(answers) answer" + (answers == 1 ? "" : "s"))
                            .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint)
                    }
                }
                if let failure { Text(failure).font(PiperTheme.ui(11.5)).foregroundStyle(PiperTheme.secondary) }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PiperTheme.page, in: RoundedRectangle(cornerRadius: AppDefaults.Notebook.fieldRadius))
            .overlay(RoundedRectangle(cornerRadius: AppDefaults.Notebook.fieldRadius).strokeBorder(PiperTheme.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, AppDefaults.Notebook.fieldPadding)
    }
}

// MARK: - Save As File

/// The popover of Save as File: the folder, the parts to include, and the text.
private struct SaveArticleForm: View {

    /// A folder that can take the file: a sidebar folder, or a folder inside the open one.
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
        model.wikiPaths.flatMap { root -> [Destination] in
            let active = root == model.wikiPath
            return [Destination(root: root, folder: "")] + (active ? model.folders.map { Destination(root: root, folder: $0) } : [])
        }
    }

    private var text: String {
        ArticleMarkdown.file(title: title, url: url, children: model.store.children(of: note.id), parts: parts, date: Date())
    }

    private var fileName: String { ArticleMarkdown.fileName(for: title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Save as File").font(PiperTheme.ui(13, weight: .semibold))
            field("Folder") {
                Picker("Folder", selection: $destination) {
                    ForEach(destinations, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
                .labelsHidden()
            }
            field("Include") {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("Highlights and your notes", isOn: $parts.highlights)
                    Toggle("Summary", isOn: $parts.summary)
                    Toggle("Agent answers", isOn: $parts.answers)
                }
                .toggleStyle(.checkbox)
            }
            ScrollView {
                Text(text)
                    .font(Font(PiperTheme.manuscript(size: AppDefaults.Notebook.previewFontSize)))
                    .foregroundStyle(PiperTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: AppDefaults.Notebook.previewHeight)
            .padding(AppDefaults.Notebook.fieldPadding)
            .background(PiperTheme.page, in: RoundedRectangle(cornerRadius: AppDefaults.Notebook.fieldRadius))
            .overlay(RoundedRectangle(cornerRadius: AppDefaults.Notebook.fieldRadius).strokeBorder(PiperTheme.rule, lineWidth: 1))
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save \(fileName)", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(destination == nil)
            }
        }
        .padding(AppDefaults.Notebook.formPadding)
        .frame(width: AppDefaults.Notebook.formWidth)
        .onAppear {
            destination = destinations.first { $0.label == lastFolder } ?? destinations.first
        }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
            content()
        }
    }

    /// Writes a new file. A file with the same name stays, and the new file
    /// gets a number.
    private func save() {
        guard let destination else { return }
        let vault = Vault(root: URL(fileURLWithPath: (destination.root as NSString).expandingTildeInPath))
        let stem = (fileName as NSString).deletingPathExtension
        var path = (destination.folder as NSString).appendingPathComponent(fileName)
        var number = 2
        while FileManager.default.fileExists(atPath: vault.root.appendingPathComponent(path).path) {
            path = (destination.folder as NSString).appendingPathComponent("\(stem)-\(number).md")
            number += 1
        }
        do {
            try vault.write(text, to: path)
            let file = vault.root.appendingPathComponent(path).path
            model.store.updateReading(note.id) { $0.savedFile = file; $0.savedAt = Date() }
            model.store.status = "Saved to " + destination.label
            lastFolder = destination.label
            model.reload()
            close()
        } catch { model.store.report(error) }
    }
}
