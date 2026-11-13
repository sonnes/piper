import AppKit
import SwiftUI
import Agents
import Captures

// MARK: Tabs and headers

/// One tab in the header of the capture panel.
struct PanelTab: View {
    let title: String
    let icon: String?
    let count: Int
    let active: Bool
    /// Shows a chevron, for a tab that opens a menu.
    var opensMenu = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 11)) }
                Text(title).lineLimit(1).truncationMode(.tail)
                if count > 0 {
                    Text("\(count)").font(PiperTheme.ui(.caption)).monospacedDigit()
                        .foregroundStyle(active ? PiperTheme.secondary : PiperTheme.faint)
                }
                if opensMenu { Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
            }
            .font(PiperTheme.ui(.body, weight: .medium))
            .foregroundStyle(active ? PiperTheme.ink : PiperTheme.secondary)
            .padding(.horizontal, 10)
            .frame(height: AppDefaults.CaptureItem.tabHeight)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: PiperTheme.radius, style: .continuous)
                        .fill(PiperTheme.card)
                        .shadow(color: PiperTheme.tabShadow, radius: 1, y: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct CaptureSectionMenu: View {
    let sections: [String]
    let current: String?
    let done: Bool
    let count: (String) -> Int
    let doneCount: Int
    let choose: (String) -> Void
    let showDone: () -> Void
    let newSection: () -> Void
    @State private var query = ""
    @FocusState private var searching: Bool

    private var matches: [String] {
        sections.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: AppDefaults.CaptureItem.actionSpacing) {
            TextField("Find a section", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searching)
            ScrollView {
                VStack(spacing: AppDefaults.CaptureItem.rowSpacing) {
                    ForEach(matches, id: \.self) { section in
                        Button { choose(section) } label: {
                            HStack {
                                Image(systemName: current == section ? "checkmark" : "tray")
                                Text(section).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(count(section))").foregroundStyle(PiperTheme.secondary)
                            }
                            .padding(.horizontal, AppDefaults.CaptureItem.actionSpacing)
                            .frame(maxWidth: .infinity, minHeight: AppDefaults.CaptureItem.buttonHitSize)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(current == section ? .isSelected : [])
                    }
                    if matches.isEmpty {
                        Text("No matching sections").foregroundStyle(PiperTheme.secondary)
                            .padding(.vertical, AppDefaults.CaptureItem.actionSpacing)
                    }
                }
            }
            .frame(maxHeight: AppDefaults.CaptureItem.sectionMenuHeight)
            Divider()
            Button(action: showDone) {
                HStack {
                    Image(systemName: done ? "checkmark" : "checkmark.circle")
                    Text("Done")
                    Spacer()
                    Text("\(doneCount)").foregroundStyle(PiperTheme.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: AppDefaults.CaptureItem.buttonHitSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("New Section…", systemImage: "plus", action: newSection)
                .controlSize(.regular)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(PiperTheme.ui(.body))
        .padding(AppDefaults.CaptureItem.horizontalPadding)
        .frame(width: AppDefaults.CaptureItem.sectionMenuWidth)
        .onAppear { searching = true }
    }
}

/// The header over one section of the capture list.
struct SectionHeader: View {
    let title: String
    let detail: String?
    let active: Bool
    let action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(PiperTheme.ui(.body, weight: .semibold))
                .foregroundStyle(active ? PiperTheme.accent : PiperTheme.ink)
            if let detail {
                Text(detail).font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary)
            }
            Spacer(minLength: 4)
            if let action {
                Button(action.0, action: action.1).buttonStyle(.text)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.top, 14).padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The header over one day of the clipboard history.
struct DayHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(PiperTheme.ui(.caption, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(PiperTheme.secondary)
            .padding(.horizontal, 6)
            .padding(.top, 14).padding(.bottom, 5)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A white card with rounded corners that groups rows.
struct CaptureCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: AppDefaults.CaptureItem.rowSpacing) { content }
            .padding(AppDefaults.CaptureItem.cardInset)
            .background(PiperTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
    }
}

/// The hairline between two rows of a card. It starts at the text.
private struct RowSeparator: View {
    let inset: CGFloat

    var body: some View {
        Rectangle().fill(PiperTheme.rule).frame(height: 0.5).padding(.leading, inset)
    }
}

/// A short time for a row: the clock time today, and the date before today.
enum RowTime {
    static func text(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: Rows

/// One clipboard text that the reader has not saved.
struct ClipboardRow: View {
    let entry: ClipboardEntry
    let showsSource: Bool
    let separated: Bool
    let paste: () -> Void
    let keep: () -> Void
    /// Saves a copied web link to Reading and opens it. Nil for other text.
    var read: (() -> Void)?
    let agents: FolderAgents
    /// Saves the text and runs a skill on it. Nil runs the default skill.
    let send: (FolderAgents.Action?) -> Void
    /// A short row for the strip under the panel list: no icon, no time, and Keep always shows.
    var compact = false
    @State private var hovered = false
    private var isCode: Bool { CaptureText.looksLikeCode(entry.text) }
    private var canSend: Bool { agents.defaultAction(for: entry.text) != nil }

    var body: some View {
        VStack(spacing: 0) {
            if separated && !compact { RowSeparator(inset: AppDefaults.CaptureItem.horizontalPadding + 22) }
            HStack(spacing: compact ? 8 : 10) {
                if !compact {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12))
                        .foregroundStyle(PiperTheme.faint)
                        .frame(width: 12)
                }
                Text(isCode ? CaptureText.firstLine(entry.text) : entry.text.replacingOccurrences(of: "\n", with: " "))
                    .font(isCode
                          ? Font(PiperTheme.manuscript(size: AppDefaults.CaptureItem.clipboardCodeFontSize))
                          : PiperTheme.ui(compact ? .secondary : AppDefaults.CaptureItem.clipboardFontSize))
                    .foregroundStyle(compact ? PiperTheme.secondary : PiperTheme.ink)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if compact {
                    if hovered {
                        if let read { Button("Read", action: read).buttonStyle(.text).help("Save to Reading and open it") }
                        if canSend { Button(agents.sendTitle) { send(nil) }.buttonStyle(.text) }
                    }
                    Button("Keep", action: keep).buttonStyle(.text).help("Save to Inbox")
                } else if hovered {
                    if let read { Button("Read", action: read).controlSize(.regular).help("Save to Reading and open it") }
                    if canSend {
                        SendButton(agents: agents, title: agents.sendTitle, sendDefault: { send(nil) }, send: send)
                    }
                    Button("Keep", action: keep).controlSize(.regular).help("Save to Inbox")
                }
                if showsSource, let source = entry.source {
                    Text(source).font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.faint).lineLimit(1).fixedSize()
                }
                if !compact {
                    Text(RowTime.text(entry.copiedAt))
                        .font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.faint).monospacedDigit().fixedSize()
                }
            }
            .font(PiperTheme.ui(.secondary))
            .padding(.horizontal, compact ? 6 : AppDefaults.CaptureItem.horizontalPadding)
            .frame(minHeight: compact ? AppDefaults.CaptureItem.stripRowHeight : AppDefaults.CaptureItem.clipboardHeight)
            .background(hovered ? PiperTheme.hover : .clear, in: RoundedRectangle(cornerRadius: compact ? 6 : 0))
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(count: 2, perform: paste)
        .contextMenu {
            Button("Paste", systemImage: "doc.on.clipboard", action: paste)
            Button("Keep in Inbox", systemImage: "tray.and.arrow.down", action: keep)
            if !agents.folders.isEmpty {
                Divider()
                Menu("Send To") { SendMenuItems(agents: agents, send: send) }
            }
        }
        .help(String(entry.text.prefix(500)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clipboard: \(String(entry.text.prefix(240)))")
        .accessibilityAction(named: "Keep in Inbox", keep)
        .accessibilityAction(named: "Paste", paste)
        .accessibilityAction(named: agents.sendTitle) { send(nil) }
    }
}

/// The number of child notes of a capture, in a yellow chip. It also shows
/// whether the list shows those notes.
struct CountChip: View {
    let text: String
    let open: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
            Text(text)
        }
        .font(PiperTheme.ui(.caption))
        .foregroundStyle(PiperTheme.markText)
        .padding(.horizontal, 6)
        .frame(height: AppDefaults.CaptureItem.chipHeight)
        .background(PiperTheme.markYellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        // A narrow row cuts the site name, not the count.
        .fixedSize()
    }
}

/// One saved note.
struct NoteRow: View {
    let note: Note
    let selected: Bool
    let select: () -> Void
    let complete: () -> Void
    let edit: () -> Void
    let newWindow: () -> Void
    let copy: (Bool) -> Void
    let prepareActions: () -> Void
    let merge: () -> Void
    let move: () -> Void
    let delete: () -> Void
    let canMerge: Bool
    /// The last session of the note.
    let session: AgentSession?
    let agents: FolderAgents
    /// Runs a skill on the note. Nil runs the default skill.
    let send: (FolderAgents.Action?) -> Void
    let openRun: () -> Void
    let stopRun: () -> Void
    /// The number of highlights and questions under the note.
    var childCount = 0
    var showsChildren = true
    var toggleChildren: () -> Void = {}
    @State private var hovered = false

    private var link: URL? { CaptureLinks(note.text).standaloneURL }
    /// A done note or a read article. Its control is a gray check and its text is gray.
    private var isComplete: Bool { note.isDone || note.reading?.finishedAt != nil }
    /// A link that no run has taken yet gets a Send button on the row.
    private var showsSend: Bool { link != nil && session == nil && !note.isDone && agents.defaultAction(for: note.text) != nil }

    private var formattedText: AttributedString {
        (try? AttributedString(markdown: note.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(note.text)
    }

    /// The application a note came from, when a selection capture recorded it.
    private var source: String? {
        guard let source = note.sources.first, source != "Clipboard", link == nil else { return nil }
        return "From " + source
    }

    /// The site of a link, and the button that shows or hides the child notes.
    @ViewBuilder private var detail: some View {
        if link != nil || childCount > 0 {
            HStack(spacing: 4) {
                if let host = link?.host() {
                    Text(host).lineLimit(1)
                    if childCount > 0 { Text("·") }
                }
                if childCount > 0 {
                    Button(action: toggleChildren) {
                        CountChip(text: childCount == 1 ? "1 note" : "\(childCount) notes", open: showsChildren)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsChildren ? "Hide notes" : "Show notes")
                }
            }
            .font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary)
            .padding(.top, 1)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                Button(action: complete) {
                    ProgressRing(progress: 0, finished: isComplete)
                        .frame(width: AppDefaults.CaptureItem.circleSize, height: AppDefaults.CaptureItem.circleSize)
                        .frame(width: AppDefaults.CaptureItem.buttonHitSize, height: AppDefaults.CaptureItem.circleSize + 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(note.isDone ? "Reopen note" : "Mark note as done")
                Button(action: select) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            if let link {
                                Text(note.reading?.title.map(CaptureText.firstLine) ?? (link.host() ?? "") + link.path())
                                    .foregroundStyle(isComplete ? PiperTheme.secondary : PiperTheme.ink)
                                    .lineLimit(1).truncationMode(.middle)
                            } else {
                                Text(formattedText)
                                    .foregroundStyle(isComplete ? PiperTheme.secondary : PiperTheme.ink)
                                    .lineSpacing(AppDefaults.CaptureItem.lineSpacing)
                                    .lineLimit(3)
                            }
                            detail
                            if let session { RunLine(session: session) }
                        }
                        .font(PiperTheme.ui(AppDefaults.CaptureItem.fontSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint("Click to select or deselect. Shift-click selects a range. Return edits the note.")
                if let session {
                    RunBadge(session: session, open: openRun)
                } else if showsSend {
                    SendButton(agents: agents, title: agents.sendTitle, sendDefault: { send(nil) }, send: send)
                }
                if hovered || selected {
                    Text(source ?? RowTime.text(note.createdAt))
                        .font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.faint).monospacedDigit().lineLimit(1).fixedSize()
                        .onTapGesture(perform: select)
                }
            }
            // The hit area centers the circle, so a smaller leading pad lines the circle up with the row text.
            .padding(.leading, AppDefaults.CaptureItem.horizontalPadding - (AppDefaults.CaptureItem.buttonHitSize - AppDefaults.CaptureItem.circleSize) / 2)
            .padding(.trailing, AppDefaults.CaptureItem.horizontalPadding)
            .padding(.vertical, AppDefaults.CaptureItem.verticalPadding)
            .frame(minHeight: AppDefaults.CaptureItem.minimumHeight)
            .background(selected ? PiperTheme.selection : hovered ? PiperTheme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: AppDefaults.InboxRow.cornerRadius))
        }
        .onHover { hovered = $0 }
        .contextMenu {
            NoteContextMenu(note: note, completeTitle: note.isDone ? "Reopen" : "Mark as Done", canMerge: canMerge,
                            session: session, agents: agents, copy: copy, complete: complete, edit: edit,
                            newWindow: newWindow, merge: merge, prepareActions: prepareActions, move: move,
                            send: send, stopRun: stopRun, delete: delete)
        }
    }
}

/// The context menu of a capture row, in the capture panel and in Inbox.
struct NoteContextMenu: View {
    let note: Note
    let completeTitle: String
    let canMerge: Bool
    let session: AgentSession?
    let agents: FolderAgents
    let copy: (Bool) -> Void
    let complete: () -> Void
    let edit: () -> Void
    let newWindow: () -> Void
    let merge: () -> Void
    let prepareActions: () -> Void
    let move: () -> Void
    let send: (FolderAgents.Action?) -> Void
    let stopRun: () -> Void
    let delete: () -> Void
    /// Saves the first web link of a note that holds more than a link.
    var addToReading: (() -> Void)?

    var body: some View {
        Button("Copy") { copy(false) }
        Button("Copy as List") { copy(true) }
        Divider()
        Button(completeTitle, action: complete)
        Button("Edit", action: edit)
        Button("Edit in New Window", action: newWindow)
        Divider()
        Button("Merge Notes", action: merge).disabled(!canMerge)
        Button("Move To…") { prepareActions(); move() }
        if !agents.folders.isEmpty {
            Divider()
            if let action = agents.defaultAction(for: note.text) {
                Button("Send to \(action.folder.name) with /\(action.skill.name)") { send(nil) }
            }
            Menu("Send To") { SendMenuItems(agents: agents, send: send) }
        }
        if session?.isActive == true {
            Button("Stop Session", action: stopRun)
        }
        if let source = note.sourceURLs.first, let url = URL(string: source), CaptureLinks.isWebURL(url) {
            Divider()
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
        }
        if let addToReading {
            Button("Add Link to Reading", action: addToReading)
        }
        Divider()
        Button("Delete", role: .destructive, action: delete)
    }
}

/// A highlight or a question under a link capture.
struct ChildNoteRow: View {
    let note: Note
    let open: () -> Void
    let openNote: () -> Void
    let addTag: () -> Void
    let copy: () -> Void
    let delete: () -> Void

    /// The quote of a highlight, or the first line of a question.
    private var line: String {
        note.text.components(separatedBy: "\n\n").first ?? note.text
    }

    var body: some View {
        let metrics = AppDefaults.ChildNote.self
        Button(action: open) {
            VStack(alignment: .leading, spacing: 3) {
                Text(line)
                    .font(.system(size: metrics.fontSize, design: .serif))
                    .foregroundStyle(PiperTheme.ink)
                    .lineSpacing(metrics.lineSpacing)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !note.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(note.tags, id: \.self) { TagChip(tag: $0) }
                    }
                }
            }
            .padding(.leading, 12).padding(.trailing, 10).padding(.top, 6).padding(.bottom, 7)
            .overlay(alignment: .leading) { Rectangle().fill(PiperTheme.rule).frame(width: metrics.ruleWidth) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, AppDefaults.CaptureItem.textInset - AppDefaults.CaptureItem.cardInset)
        .padding(.trailing, AppDefaults.CaptureItem.horizontalPadding)
        .accessibilityHint("Shows the note in the article")
        .contextMenu {
            Button("Open Note", action: openNote)
            Button("Add Tag…", action: addTag)
            Button("Copy", action: copy)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }
}

/// One tag of a note. Highlight, question, and the highlight colors have their
/// own colors. Every other tag is blue.
struct TagChip: View {
    let tag: String

    private var swatch: Color? { Self.markColor(tag) }

    private var colors: (text: Color, fill: Color) {
        switch tag {
        case ReadingList.highlightTag: return (PiperTheme.tagHighlight, PiperTheme.tagHighlightFill)
        case ReadingList.questionTag: return (PiperTheme.tagQuestion, PiperTheme.tagQuestionFill)
        default: return swatch == nil ? (PiperTheme.tagOther, PiperTheme.tagOtherFill) : (PiperTheme.secondary, PiperTheme.hover)
        }
    }

    /// The color of a highlight color tag, in the order of `ReaderAssistant.colors`. Nil for any other tag.
    static func markColor(_ tag: String) -> Color? {
        let marks = [PiperTheme.markYellow, PiperTheme.markGreen, PiperTheme.markPink]
        return ReaderAssistant.colors.firstIndex(of: tag).flatMap { marks.indices.contains($0) ? marks[$0] : nil }
    }

    var body: some View {
        let metrics = AppDefaults.ChildNote.self
        HStack(spacing: 4) {
            if let swatch {
                Circle().fill(swatch).frame(width: metrics.swatchSize, height: metrics.swatchSize)
            }
            Text(tag)
        }
        .font(PiperTheme.ui(metrics.tagFontSize, weight: .medium))
        .foregroundStyle(colors.text)
        .padding(.horizontal, 6)
        .frame(height: metrics.tagHeight)
        .background(colors.fill, in: Capsule())
    }
}

// MARK: Sheets

/// The sections, with a checkmark on the one that new notes go to.
struct SectionPicker: View {
    let sections: [String]
    let current: String
    let moving: Bool
    let newSection: () -> Void
    let select: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(moving ? "Move To" : "Capture To").font(PiperTheme.ui(.body, weight: .semibold))
                .padding(.horizontal, 8).padding(.bottom, 8)
            ForEach(sections, id: \.self) { section in
                MenuRow(title: section, checked: !moving && section == current) { select(section) }
            }
            if !moving {
                Rule().padding(.horizontal, 8).padding(.vertical, 5)
                MenuRow(title: "New Section…", checked: false, action: newSection)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.top, 14)
        }
        .padding(16).frame(width: 280)
    }
}

private struct MenuRow: View {
    let title: String
    let checked: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    .opacity(checked ? 1 : 0).frame(width: 12)
                Text(title).lineLimit(1)
                Spacer()
            }
            .font(PiperTheme.ui(.body))
            .foregroundStyle(hovered ? Color.white : PiperTheme.ink)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(hovered ? PiperTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// Names a new section. Return creates it and makes it the target of new notes.
struct NewSectionSheet: View {
    let sections: [String]
    let create: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Section").font(PiperTheme.ui(.body, weight: .semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create", action: submit).keyboardShortcut(.defaultAction).disabled(trimmed.isEmpty)
            }
        }
        .padding(16).frame(width: 280)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        create(sections.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed)
    }
}

/// Edits the text of one note, in a sheet or in its own window.
struct NoteEditor: View {
    let model: AppModel
    @Bindable var session: CaptureEditSession
    let save: () -> Void
    var cancel: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel, session: CaptureEditSession, cancel: (() -> Void)? = nil, save: @escaping () -> Void) {
        self.model = model
        self.session = session
        self.cancel = cancel
        self.save = save
    }
    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $session.text).font(PiperTheme.ui(.reading)).lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .accessibilityLabel("Edit note text")
                .frame(minHeight: 180)
            Rule()
            HStack(spacing: 8) {
                if let error = model.store.errorMessage {
                    Text(error).font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.danger).textSelection(.enabled).lineLimit(2)
                } else if session.hasChanges {
                    Text("Edited").font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.secondary)
                }
                Spacer()
                Button("Cancel") { if let cancel { cancel() } else { dismiss() } }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 480, height: cancel == nil ? 300 : nil)
        .background(PiperTheme.page)
        .foregroundStyle(PiperTheme.ink)
        .tint(PiperTheme.accent)
        .interactiveDismissDisabled(session.hasChanges)
        .onDisappear { model.captureEdits.removeValue(forKey: session.id) }
    }
}
