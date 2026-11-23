import AppKit
import SwiftUI
import PiperCore
import Agents
import Captures

private enum CaptureSheet: Identifiable {
    case sections(moving: Bool), newSection, edit(CaptureEditSession)
    var id: String {
        switch self {
        case .sections(let moving): return moving ? "move" : "sections"
        case .newSection: return "newSection"
        case .edit: return "edit"
        }
    }
}

/// What the capture list shows.
enum CaptureListContent: Equatable {
    /// The whole clipboard history, grouped by day.
    case clipboard
    case archived
    /// The feed paper: one stream of the captures of a section, or of every
    /// section when the section is nil.
    case stream(section: String?)
}

/// The capture list of the feed paper.
///
/// The list is a checklist with the add field at the top. The feed paper
/// selects sections on the Inbox index.
struct CaptureView: View {
    @Bindable var store: CaptureStore
    @Bindable var model: AppModel
    let acceptsKeyboard: (NSWindow) -> Bool
    let focusNotes: () -> Void
    let selectCapture: (UUID?) -> Void
    /// Opens one capture as a reader paper, after a click or Return.
    let openCapture: (UUID) -> Void
    /// What the feed paper shows.
    let content: CaptureListContent
    let composerRequest: UUID?

    init(model: AppModel, content: CaptureListContent,
         composerRequest: UUID? = nil,
         acceptsKeyboard: @escaping (NSWindow) -> Bool,
         focusNotes: @escaping () -> Void = {},
         selectCapture: @escaping (UUID?) -> Void = { _ in },
         openCapture: @escaping (UUID) -> Void = { _ in }) {
        self.content = content
        self.composerRequest = composerRequest
        self.acceptsKeyboard = acceptsKeyboard
        self.focusNotes = focusNotes
        self.selectCapture = selectCapture
        self.openCapture = openCapture
        self.model = model
        self.store = model.store
    }

    @State private var sheet: CaptureSheet?
    @State private var keyMonitor: Any?
    @State private var selectionAnchor: UUID?
    @State private var showingSearch = false
    @FocusState private var searching: Bool
    @State private var composing = false
    @State private var showsDoneToday = false
    /// The height of the text in the add field, which sets the height of the field.
    @State private var composerTextHeight: CGFloat = 0
    /// The highlighted row of the skill list over the composer.
    @State private var completionIndex = 0
    /// The skill the reader picked from the list, which also picks the folder.
    @State private var chosenAction: FolderAgents.Action?
    /// True while modifier-clicks or the keyboard select several captures.
    @State private var checking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isStream: Bool {
        if case .stream = content { return true }
        return false
    }
    /// The section of the stream. Nil shows every section.
    private var streamSection: String? {
        if case .stream(let section) = content { return section }
        return nil
    }
    private var filter: InboxStream.Filter { model.inboxFilter(for: streamSection) }
    private var stream: InboxStream {
        InboxStream(notes: store.notes, section: streamSection, filter: filter, query: store.query)
    }
    private var searchMode: Bool { showingSearch || !store.query.isEmpty }
    private var archiveGroups: [InboxStream.Group] {
        InboxStream.archive(notes: store.notes, query: store.query)
    }
    private var matchingNotes: [Note] { matchingNotes(in: isStream ? stream : nil) }

    /// The notes of the list in order. A stream that the caller built is used as it is.
    private func matchingNotes(in stream: InboxStream?) -> [Note] {
        if let stream { return stream.notes }
        return content == .archived ? archiveGroups.flatMap(\.notes) : []
    }
    private var clipboardEntries: [ClipboardEntry] {
        model.clipboard.entries.filter {
            store.query.isEmpty || $0.text.localizedCaseInsensitiveContains(store.query)
        }
    }
    private var showsComposer: Bool { isStream }
    private var canSave: Bool { !model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }
    private var agents: FolderAgents { model.agents }

    /// The skills that match the command in the composer.
    private var completions: [FolderAgents.Action] {
        guard showsComposer, composing, let partial = SlashCommand.partialName(model.composerDraft) else { return [] }
        return Array(agents.completions(for: partial).prefix(AppDefaults.Agents.completionLimit))
    }

    /// The folder and skill that Return runs, when the composer holds a command.
    private var composedAction: FolderAgents.Action? {
        guard let command = SlashCommand(model.composerDraft) else { return nil }
        if let chosenAction, chosenAction.skill.name == command.name { return chosenAction }
        return agents.action(for: command)
    }

    var body: some View {
        // The stream is built once for each drawing of the list.
        let stream = isStream ? self.stream : nil
        let matching = matchingNotes(in: stream)
        VStack(spacing: 0) {
            if searchMode { paneHeader(matches: matching.count) }
            if showsComposer { paperComposer }
            switch content {
            case .archived:
                archiveList
            case .stream:
                streamList(stream ?? self.stream).overlay(alignment: .bottom) { skillList }
            case .clipboard: clipboardHistory
            }
            if checking && !store.selection.isEmpty { selectionBar }
        }
        .background(PiperTheme.page)
        .foregroundStyle(PiperTheme.ink)
        .tint(PiperTheme.brand)
        .accentColor(PiperTheme.brand)
        .sheet(item: $sheet) { item in
            switch item {
            case .sections(let moving):
                SectionPicker(sections: store.sections, current: store.activeSection, moving: moving,
                              newSection: { sheet = .newSection }) { section in
                    if moving { store.move(to: section) }
                    else { chooseSection(section) }
                    sheet = nil
                }
            case .newSection:
                NewSectionSheet(sections: store.sections) { name in
                    if store.chooseSection(name) {
                        store.status = "Capturing to \(store.activeSection)"
                        sheet = nil
                    }
                }
            case .edit(let session):
                NoteEditor(model: model, session: session) {
                    if model.saveCaptureEdit(session) { sheet = nil }
                }
            }
        }
        .onChange(of: store.query) { _, _ in clearSelection() }
        .onChange(of: content) { _, _ in
            clearSelection()
            composing = false
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            installKeyboardShortcuts()
        }
        .onChange(of: matching.map(\.id)) { _, ids in
            guard NSApp.keyWindow?.windowController is FeedPaperController else { return }
            store.selection.formIntersection(ids)
        }
        .onChange(of: store.selection) { _, selection in
            if selection.isEmpty { checking = false }
            selectCapture(selection.count == 1 ? selection.first : nil)
        }
        .onChange(of: model.composerDraft) { _, _ in completionIndex = 0 }
        .onChange(of: composerRequest, initial: true) { _, request in
            guard request != nil, showsComposer else { return }
            clearSelection()
            endSearch()
        }
        .onAppear { installKeyboardShortcuts() }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    // MARK: Headers

    /// The search field over a list of the feed paper, after Command-F. The
    /// paper title names the list.
    private func paneHeader(matches: Int) -> some View {
        searchField(matches: matches)
            .padding(.horizontal, AppDefaults.Papers.composerPadding.leading)
            .padding(.top, AppDefaults.Papers.composerPadding.top)
    }

    private func searchField(matches: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(PiperTheme.faint)
            TextField("Search", text: $store.query)
                .textFieldStyle(.plain).focused($searching)
                .font(PiperTheme.paperUI(.row))
                .accessibilityLabel(content == .clipboard ? "Search the clipboard" : "Search notes")
                .onAppear {
                    if showingSearch { DispatchQueue.main.async { searching = true } }
                }
            if searchMode {
                let matches = content == .clipboard ? clipboardEntries.count : matches
                Text(count(matches, "match", "matches"))
                    .font(PiperTheme.paperUI(.body))
                    .foregroundStyle(PiperTheme.faint).lineLimit(1).fixedSize()
            }
            if !store.query.isEmpty {
                Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PiperTheme.faint) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: AppDefaults.Papers.composerHeight)
        .background(PiperTheme.paperTint, in: RoundedRectangle(cornerRadius: AppDefaults.Papers.rowRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppDefaults.Papers.rowRadius + 2)
                .strokeBorder(searching ? PiperTheme.brand : .clear, lineWidth: 3)
                .padding(-2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Lists

    /// The Inbox of the feed paper: Continue Reading, one group for each day,
    /// and the captures done today.
    private func streamList(_ stream: InboxStream) -> some View {
        let doneToday = filter == .reading || !store.query.isEmpty ? []
            : InboxStream.doneToday(notes: store.notes, section: streamSection).filter { filter == .all || !$0.isArticle }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(stream.groups, id: \.title) { group in
                        Section {
                            ForEach(Array(group.notes.enumerated()), id: \.element.id) { index, note in
                                inboxRow(note, style: rowStyle(note, in: group, at: index)).id(note.id)
                            }
                        } header: {
                            PaperGroupHeader(title: group.title,
                                             action: group.kind == .started && filter == .all ? ("See All", { setFilter(.reading) }) : nil)
                        }
                    }
                    if !doneToday.isEmpty {
                        PaperDoneToday(count: doneToday.count, shown: showsDoneToday) { showsDoneToday.toggle() }
                        if showsDoneToday {
                            ForEach(doneToday) { note in
                                inboxRow(note, style: note.isArticle ? .compact : .note).id(note.id)
                            }
                        }
                    }
                }
                .padding(AppDefaults.Papers.listPadding)
            }
            .overlay {
                if stream.groups.isEmpty && doneToday.isEmpty {
                    if !store.query.isEmpty {
                        PaperEmpty(symbol: "magnifyingglass", title: "No Results", detail: "Try another word.")
                    } else if filter == .reading {
                        PaperEmpty(symbol: "book", title: "Nothing to Read", detail: "On a web page, press Shift twice to save it here.")
                    } else {
                        PaperEmpty(symbol: "tray", title: "No Notes", detail: "Type a note above, or press Shift twice in another app.")
                    }
                }
            }
            .onChange(of: selectionAnchor) { _, id in
                if let id { withAnimation(motion) { proxy.scrollTo(id) } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The done captures, one group for each month, in the rows of the Inbox stream.
    private var archiveList: some View {
        let groups = archiveGroups
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.title) { group in
                        Section {
                            ForEach(group.notes) { note in
                                inboxRow(note, style: note.isArticle ? .compact : .note).id(note.id)
                            }
                        } header: {
                            PaperGroupHeader(title: group.title)
                        }
                    }
                }
                .padding(AppDefaults.Papers.listPadding)
            }
            .overlay {
                if groups.isEmpty {
                    if store.query.isEmpty {
                        PaperEmpty(symbol: "checkmark.circle", title: "No Done Notes", detail: "Notes that you mark as done show here.")
                    } else {
                        PaperEmpty(symbol: "magnifyingglass", title: "No Results", detail: "Try another word.")
                    }
                }
            }
            .onChange(of: selectionAnchor) { _, id in
                if let id { withAnimation(motion) { proxy.scrollTo(id) } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The first started article of All shows its progress and highlights.
    /// Each other started article in All is one line.
    private func rowStyle(_ note: Note, in group: InboxStream.Group, at index: Int) -> InboxRow.Style {
        guard note.isArticle else { return .note }
        switch group.kind {
        case .started: return .compact
        case .upNext: return .link
        case .finished, .month: return .compact
        case .day:
            let started = note.reading?.openedAt != nil || note.reading?.finishedAt != nil || !store.children(of: note.id).isEmpty
            return started ? .compact : .link
        }
    }

    private func inboxRow(_ note: Note, style: InboxRow.Style) -> some View {
        let session = agents.latestSession(for: note)
        let finished = note.reading?.finishedAt != nil
        return InboxRow(
            note: note, style: style, selected: store.selection.contains(note.id),
            section: streamSection == nil ? note.section : nil,
            children: store.children(of: note.id),
            session: session,
            select: { openNote(note.id) },
            complete: { note.isDone || style == .note ? store.toggleDone(note.id) : toggleRead(note) },
            openRun: { openRun(for: note) },
            openChild: { child in
                model.showHighlight(child.id, in: note.id)
                openNote(note.id)
            },
            menu: NoteContextMenu(
                note: note,
                completeTitle: note.isDone ? "Reopen" : style == .note ? "Mark as Done" : finished ? "Read Again" : "Mark as Read",
                canMerge: store.selection.contains(note.id) && store.selection.count > 1,
                session: session, agents: agents,
                copy: { asList in
                    if !store.selection.contains(note.id) { store.selection = [note.id] }
                    store.copy(asList: asList)
                },
                complete: { note.isDone || style == .note ? store.toggleDone(note.id) : toggleRead(note) },
                edit: { sheet = .edit(model.editCapture(note)) },
                newWindow: { model.openNoteEditor?(note) },
                merge: { store.merge() },
                prepareActions: { if !store.selection.contains(note.id) { store.selection = [note.id] } },
                move: { sheet = .sections(moving: true) },
                send: { action in agents.send(note, action: action) },
                stopRun: { if let session { agents.runner.stop(session) } },
                delete: {
                    if !store.selection.contains(note.id) { store.selection = [note.id] }
                    store.deleteSelection()
                },
                addToReading: addToReading(note)))
    }

    /// Saves the first web link of a note that holds more than a link, and opens it.
    private func addToReading(_ note: Note) -> (() -> Void)? {
        guard !note.isArticle, let url = CaptureLinks(note.text).urls.first else { return nil }
        return {
            guard let article = store.saveArticle(url, source: note.sources.first) else { return }
            model.showArticle?(article.id)
        }
    }

    /// Marks an article as read, or opens it again. A read article stays in
    /// Finished This Week, then goes to Done.
    private func toggleRead(_ note: Note) {
        if note.reading?.finishedAt == nil {
            store.updateReading(note.id) { $0.finishedAt = Date(); $0.progress = 1 }
        } else {
            store.updateReading(note.id) { $0.finishedAt = nil; $0.progress = 0; $0.block = nil }
        }
    }

    private func setFilter(_ filter: InboxStream.Filter) {
        model.inboxFilters[streamSection ?? ""] = filter
        clearSelection()
    }

    /// The clipboard history on the feed paper: one row for each copy, under its day.
    private var clipboardHistory: some View {
        let days = Dictionary(grouping: clipboardEntries) { Calendar.current.startOfDay(for: $0.copiedAt) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    Section {
                        ForEach(days[day] ?? []) { entry in
                            PaperClipboardRow(entry: entry, keep: { keep(entry) }, copy: { copy(entry) },
                                              read: readAction(entry), agents: agents, send: { send(entry, $0) })
                        }
                    } header: {
                        PaperGroupHeader(title: Self.dayTitle(day))
                    }
                }
                if !clipboardEntries.isEmpty && store.query.isEmpty {
                    Button("Clear History") { withAnimation(motion) { model.clipboard.clear() } }
                        .buttonStyle(.plain)
                        .font(PiperTheme.paperUI(.body, weight: .medium)).foregroundStyle(PiperTheme.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
            }
            .padding(AppDefaults.Papers.listPadding)
        }
        .overlay {
            if clipboardEntries.isEmpty {
                if store.query.isEmpty {
                    PaperEmpty(symbol: "doc.on.clipboard", title: "No Copies", detail: "Text you copy appears here for 7 days.")
                } else {
                    PaperEmpty(symbol: "magnifyingglass", title: "No Results", detail: "Try another word.")
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Selection and composer

    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: AppDefaults.CaptureItem.actionSpacing) {
            HStack {
                Text("\(store.selection.count) selected")
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.secondary)
                Spacer()
                Button("Cancel") { clearSelection() }
                    .buttonStyle(.plain).font(PiperTheme.paperUI(.body, weight: .medium)).foregroundStyle(PiperTheme.brand)
                    .help("Clear the selection · Escape")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: AppDefaults.CaptureItem.actionMinimumWidth),
                                         spacing: AppDefaults.CaptureItem.actionSpacing)],
                      spacing: AppDefaults.CaptureItem.actionSpacing) {
                if !agents.folders.isEmpty {
                    SendButton(agents: agents, title: "Send", sendDefault: { agents.sendSelection() },
                               send: { agents.sendSelection(action: $0) })
                        .help("Send each note with its default skill · ⇧⌘Return")
                }
                Button(content == .archived ? "Reopen" : "Mark as Done") { store.completeSelection() }
                    .help("Mark as Done or Reopen · Space")
                Button("Merge") { store.merge() }
                    .disabled(store.selection.count < 2).help("Merge Notes · ⇧⌘M")
                Button("Move…") { sheet = .sections(moving: true) }
                Button("Copy") { store.copy(asList: false) }.help("Copy · ⌘C. Copy as List · ⇧⌘C")
                Button("Delete") { store.deleteSelection() }.help("Delete Notes · Delete")
            }
        }
        .controlSize(.regular)
        .font(PiperTheme.paperUI(.body))
        .padding(.horizontal, AppDefaults.Papers.footMargin)
        .padding(.vertical, AppDefaults.CaptureItem.actionSpacing)
        .overlay(alignment: .top) { Rule() }
    }

    /// The capture field of the feed paper, on the first line of the paper.
    /// It grows with its text, up to `Composer.maxLines`.
    private var paperComposer: some View {
        let metrics = AppDefaults.Composer.self
        let papers = AppDefaults.Papers.self
        let inset = metrics.paperTextInset.height * 2
        let height = min(max(composerTextHeight, papers.composerHeight),
                         metrics.paperLineHeight * CGFloat(metrics.maxLines) + inset)
        return HStack(alignment: .top, spacing: 0) {
            Text("+")
                .font(PiperTheme.paperUI(.reading))
                .foregroundStyle(PiperTheme.paperFaint)
                .frame(width: papers.composerTextInset, height: papers.composerHeight)
                .accessibilityHidden(true)
            CaptureEditor(text: $model.composerDraft, focused: $composing,
                          placeholder: "Add to \(store.activeSection)", paper: true,
                          contentHeight: { composerTextHeight = $0 })
                .frame(height: height)
            if composing, composedAction != nil || !completions.isEmpty {
                Text(inboxHint)
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                    .lineLimit(1).help(inboxHint)
                    .padding(.trailing, 14)
                    .frame(height: papers.composerHeight)
                    .allowsHitTesting(false)
            }
        }
        .background(PiperTheme.paperTint, in: RoundedRectangle(cornerRadius: papers.rowRadius, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: papers.rowRadius + papers.focusRingWidth, style: .continuous)
                .fill(composing ? PiperTheme.brand : .clear)
                .padding(-papers.focusRingWidth)
        }
        .padding(papers.composerPadding)
    }

    private var inboxHint: String {
        if composing, let action = composedAction { return "Return runs /\(action.skill.name) in \(action.folder.name)" }
        if !completions.isEmpty { return "Tab completes · ↑↓ choose" }
        return store.status == "Local notes" ? "⌘K section" : store.status
    }

    /// The skills that match the command in the composer, over the bottom of the list.
    @ViewBuilder private var skillList: some View {
        if !completions.isEmpty {
            SkillCompletions(actions: completions, selected: min(completionIndex, completions.count - 1)) {
                complete($0, run: false)
            }
            .padding(.horizontal, AppDefaults.Composer.margin)
            .padding(.bottom, 4)
        }
    }

    // MARK: Values

    private func count(_ value: Int, _ one: String, _ many: String) -> String {
        "\(value) \(value == 1 ? one : many)"
    }

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: Behavior

    private func clearSelection() {
        store.selection.removeAll()
        selectionAnchor = nil
    }

    private func chooseSection(_ section: String) {
        guard section != store.activeSection else { return }
        clearSelection()
        store.chooseSection(section)
    }

    private func beginSearch() {
        composing = false
        showingSearch = true
        searching = true
    }

    private func endSearch() {
        store.query = ""
        showingSearch = false
        searching = false
        composing = showsComposer
    }

    /// Puts a clipboard entry back on the clipboard.
    private func copy(_ entry: ClipboardEntry) {
        if Self.copy(entry.text) { store.status = "Copied" }
    }

    /// Puts the text on the clipboard as plain text.
    @discardableResult
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Saves a copied web link to Reading and opens it as a reader paper.
    private func readAction(_ entry: ClipboardEntry) -> (() -> Void)? {
        guard let url = CaptureLinks(entry.text).standaloneURL else { return nil }
        return {
            guard let article = model.store.saveArticle(url, source: entry.source ?? "Clipboard") else { return }
            model.showArticle?(article.id)
        }
    }

    /// Saves a clipboard entry to Inbox.
    private func keep(_ entry: ClipboardEntry) {
        withAnimation(motion) {
            if model.clipboard.save(entry.id) { clearSelection() }
        }
    }

    /// Saves a clipboard text to Inbox and runs a skill on the new note.
    private func send(_ entry: ClipboardEntry, _ action: FolderAgents.Action?) {
        withAnimation(motion) {
            if agents.send(entry, from: model.clipboard, action: action) != nil { clearSelection() }
        }
    }

    /// Opens the file that a finished session wrote. Any other session shows its note.
    private func openRun(for note: Note) {
        guard let session = agents.latestSession(for: note) else { return }
        if session.state == .idle, let file = session.primaryFile {
            model.openRunFile(file, in: session.folder)
        } else {
            store.selection = [note.id]
            selectionAnchor = note.id
        }
    }

    /// Puts a skill from the list into the composer. A skill that takes no
    /// argument runs at once when the reader pressed Return.
    private func complete(_ action: FolderAgents.Action, run: Bool) {
        chosenAction = action
        if run && action.skill.argumentHint == nil {
            model.composerDraft = "/" + action.skill.name
            saveNote()
        } else {
            model.composerDraft = "/" + action.skill.name + " "
        }
    }

    /// Opens one capture as a reader paper, and ends a selection of several.
    private func openNote(_ id: UUID) {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        if !flags.intersection([.command, .shift]).isEmpty {
            selectNote(id, modifiers: flags)
            checking = !store.selection.isEmpty
            return
        }
        composing = false
        searching = false
        focusNotes()
        checking = false
        store.selection = [id]
        selectionAnchor = id
        openCapture(id)
    }

    private func selectNote(_ id: UUID, modifiers: NSEvent.ModifierFlags? = nil) {
        let flags = modifiers ?? NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        composing = false
        showingSearch = searchMode && !store.query.isEmpty
        searching = false
        focusNotes()
        if flags.contains(.shift), let anchor = selectionAnchor,
           let start = matchingNotes.firstIndex(where: { $0.id == anchor }),
           let end = matchingNotes.firstIndex(where: { $0.id == id }) {
            store.selection.formUnion(matchingNotes[min(start, end)...max(start, end)].map(\.id))
        } else {
            store.toggleSelection(id)
            selectionAnchor = id
        }
    }

    private func saveNote() {
        guard canSave else { return }
        if let command = SlashCommand(model.composerDraft), let action = composedAction {
            if agents.run(command, action: action) != nil {
                model.composerDraft = ""
                chosenAction = nil
                store.query = ""
                showingSearch = false
                store.selection.removeAll()
                composing = true
            }
            return
        }
        let createsSection = model.composerDraft.hasPrefix("# ") && !model.composerDraft.contains("\n")
        if store.add(model.composerDraft) {
            if createsSection { store.status = "Capturing to \(store.activeSection)" }
            model.composerDraft = ""
            store.query = ""
            showingSearch = false
            store.selection.removeAll()
            composing = true
        }
    }

    private func installKeyboardShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = PaperKey.focusedWindow, window.attachedSheet == nil,
                  acceptsKeyboard(window) else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let textView = window.firstResponder as? NSTextView
            if textView?.hasMarkedText() == true { return event }
            let editingText = textView != nil
            let plain = flags.isDisjoint(with: [.shift, .command, .option, .control])
            if editingText, plain, !completions.isEmpty {
                let current = min(completionIndex, completions.count - 1)
                switch event.keyCode {
                case 125: completionIndex = min(current + 1, completions.count - 1); return nil
                case 126: completionIndex = max(current - 1, 0); return nil
                case 48: complete(completions[current], run: false); return nil
                case 36: complete(completions[current], run: true); return nil
                case 53: model.composerDraft = ""; return nil
                default: break
                }
            }
            if event.keyCode == 36, flags.intersection([.command, .shift, .option, .control]) == [.command, .shift], !editingText, !store.selection.isEmpty {
                agents.sendSelection()
                return nil
            }
            if event.keyCode == 53 {
                if !store.selection.isEmpty { store.selection.removeAll(); composing = showsComposer }
                else if searchMode { endSearch() }
                else { return event }
                return nil
            }
            if event.keyCode == 36, !flags.contains(.shift), !flags.contains(.option), !flags.contains(.control) {
                if composing { saveNote(); return nil }
                if !editingText, let note = store.selectedNotes.first {
                    if flags.contains(.command) { model.openNoteEditor?(note) }
                    else { openCapture(note.id) }
                    return nil
                }
            }
            if !editingText, !flags.contains(.command), !flags.contains(.option), !flags.contains(.control) {
                if [51, 117].contains(event.keyCode), !store.selection.isEmpty { store.deleteSelection(); return nil }
                if event.keyCode == 49, !store.selection.isEmpty { store.completeSelection(); return nil }
                if [125, 126].contains(event.keyCode), !flags.contains(.shift),
                   model.scrollReader(down: event.keyCode == 125, in: window) {
                    return nil
                }
                if [125, 126].contains(event.keyCode), !matchingNotes.isEmpty {
                    let current = matchingNotes.firstIndex { $0.id == selectionAnchor }
                    let next = max(0, min(matchingNotes.count - 1, (current ?? (event.keyCode == 125 ? -1 : matchingNotes.count)) + (event.keyCode == 125 ? 1 : -1)))
                    let id = matchingNotes[next].id
                    if flags.contains(.shift) { store.selection.insert(id); checking = true }
                    else { store.selection = [id]; checking = false }
                    selectionAnchor = id
                    return nil
                }
            }
            guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "k": sheet = .sections(moving: false)
            case "f": beginSearch()
            case "a" where !editingText: store.selection = Set(matchingNotes.map(\.id)); checking = true
            case "c" where !editingText && !store.selection.isEmpty: store.copy(asList: flags.contains(.shift))
            case "m" where flags.contains(.shift) && !editingText: store.merge()
            case "z" where !editingText: store.undo()
            default: return event
            }
            return nil
        }
    }
}
