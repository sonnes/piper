import AppKit
import SwiftUI
import PiperCore
import Agents
import Captures

private enum PanelSheet: Identifiable {
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
    /// The panel: the active section, or every section during a search.
    case sections
    /// The whole clipboard history, grouped by day.
    case clipboard
    case archived
    /// The main window: one stream of the captures of a section, or of every
    /// section when the section is nil.
    case stream(section: String?)
}

/// The capture list, in the capture panel and in the Inbox pane of the main window.
///
/// The list is a checklist with the add field at the top. The panel shows one
/// section at a time and selects it with tabs. The main window selects
/// sections from the children of Inbox in the sidebar.
struct CaptureView: View {
    @Bindable var store: CaptureStore
    @Bindable var model: AppModel
    let embedded: Bool
    let acceptsKeyboard: (NSWindow) -> Bool
    let focusNotes: () -> Void
    let selectCapture: (UUID?) -> Void
    /// What the main window shows. The panel keeps its own selection.
    let embeddedContent: CaptureListContent
    let composerRequest: UUID?

    init(model: AppModel, embedded: Bool = false,
         content: CaptureListContent = .sections,
         composerRequest: UUID? = nil,
         acceptsKeyboard: @escaping (NSWindow) -> Bool = { $0 is CapturePanel },
         focusNotes: @escaping () -> Void = {},
         selectCapture: @escaping (UUID?) -> Void = { _ in }) {
        self.embedded = embedded
        self.embeddedContent = content
        self.composerRequest = composerRequest
        self.acceptsKeyboard = acceptsKeyboard
        self.focusNotes = focusNotes
        self.selectCapture = selectCapture
        self.model = model
        self.store = model.store
    }

    @State private var sheet: PanelSheet?
    @State private var keyMonitor: Any?
    @State private var selectionAnchor: UUID?
    @State private var showingSearch = false
    @State private var showingSections = false
    @FocusState private var searching: Bool
    @State private var composing = false
    @State private var panelContent = CaptureListContent.sections
    @State private var showsDoneToday = false
    /// The height of the text in the add field, which sets the height of the field.
    @State private var composerTextHeight: CGFloat = 0
    @AppStorage(AppDefaults.Key.clipboardStripFolded) private var clipboardFolded = false
    /// The highlighted row of the skill list over the composer.
    @State private var completionIndex = 0
    /// The skill the reader picked from the list, which also picks the folder.
    @State private var chosenAction: FolderAgents.Action?
    /// The captures whose child notes the reader showed or hid. A list
    /// shows or hides child notes by default, and each capture here differs
    /// from that default.
    @State private var toggledParents: Set<UUID> = []
    /// True while modifier-clicks or the keyboard select several captures.
    @State private var checking = false
    /// The child note that the Add Tag field adds to.
    @State private var taggedNote: UUID?
    @State private var tagText = ""
    @AppStorage(AppDefaults.Key.accessibilityTipDismissed) private var tipDismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var content: CaptureListContent { embedded ? embeddedContent : panelContent }
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
    /// The sections of the panel list: the active one, or each one with a match during a search.
    private var displayedSections: [String] {
        searchMode ? store.sections.filter { !store.visibleNotes(in: $0).isEmpty } : [store.activeSection]
    }
    private var archiveGroups: [InboxStream.Group] {
        InboxStream.archive(notes: store.notes, query: store.query)
    }
    private var matchingNotes: [Note] { matchingNotes(in: isStream ? stream : nil) }

    /// The notes of the list in order. A stream that the caller built is used as it is.
    private func matchingNotes(in stream: InboxStream?) -> [Note] {
        if let stream { return stream.notes }
        if content == .archived { return archiveGroups.flatMap(\.notes) }
        return content == .clipboard ? [] : displayedSections.flatMap { panelNotes(in: $0) }
    }
    /// The open notes of a section in the panel, the newest first, so a new
    /// note shows under the add field.
    private func panelNotes(in section: String) -> [Note] {
        store.visibleNotes(in: section).reversed()
    }
    private var clipboardEntries: [ClipboardEntry] {
        model.clipboard.entries.filter {
            store.query.isEmpty || $0.text.localizedCaseInsensitiveContains(store.query)
        }
    }
    /// The clipboard texts that match a search in the panel.
    private var recentClipboard: [ClipboardEntry] {
        guard !embedded, content == .sections, searchMode else { return [] }
        return clipboardEntries
    }
    private var showsComposer: Bool { content == .sections || isStream }
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
            if embedded { paneHeader(stream, matches: matching.count) } else { panelHeader(matches: matching.count) }
            if !embedded && !model.accessibilityEnabled && !tipDismissed { accessibilityTip }
            if showsComposer { composer }
            switch content {
            case .sections:
                sectionList.overlay(alignment: .bottom) { skillList }
            case .archived:
                archiveList
            case .stream:
                streamList(stream ?? self.stream).overlay(alignment: .bottom) { skillList }
            case .clipboard: clipboardHistory
            }
            if embedded ? checking && !store.selection.isEmpty : !store.selection.isEmpty { selectionBar }
            if !embedded && content == .sections && !searchMode && store.selection.isEmpty { clipboardStrip }
            if !embedded { hints }
        }
        .background {
            if embedded {
                PiperTheme.page
            } else {
                ZStack { PiperTheme.panel; WindowDragArea() }
            }
        }
        .foregroundStyle(PiperTheme.ink)
        .tint(PiperTheme.accent)
        .accentColor(PiperTheme.accent)
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
                        panelContent = .sections
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
        .alert("Piper", isPresented: Binding(get: { !embedded && store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: store.query) { _, _ in clearSelection() }
        .alert("Add Tag", isPresented: Binding(get: { taggedNote != nil }, set: { if !$0 { taggedNote = nil } })) {
            TextField("Tag", text: $tagText)
            Button("Add") {
                if let id = taggedNote { store.addTag(tagText, to: id) }
                taggedNote = nil
            }
            Button("Cancel", role: .cancel) { taggedNote = nil }
        } message: { Text("A tag is one word, such as sqlite.") }
        .onChange(of: content) { _, _ in
            clearSelection()
            if embedded { composing = false }
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            installKeyboardShortcuts()
        }
        .onChange(of: matching.map(\.id)) { _, ids in
            guard let window = NSApp.keyWindow,
                  embedded ? window.windowController is MainWindowController : window is CapturePanel else { return }
            store.selection.formIntersection(ids)
        }
        .onChange(of: store.selection) { _, selection in
            if selection.isEmpty { checking = false }
            selectCapture(selection.count == 1 ? selection.first : nil)
        }
        .onChange(of: model.composerDraft) { _, _ in completionIndex = 0 }
        .onChange(of: composerRequest, initial: true) { _, request in
            guard embedded, request != nil, showsComposer else { return }
            clearSelection()
            endSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard !embedded, let window = notification.object as? CapturePanel, window.attachedSheet == nil else { return }
            agents.refresh(paths: model.wikiPaths)
            if store.selection.isEmpty && !searchMode && content == .sections { composing = true }
        }
        .onAppear {
            if !embedded { composing = showsComposer }
            installKeyboardShortcuts()
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    // MARK: Headers

    private func panelHeader(matches: Int) -> some View {
        HStack(spacing: 2) {
            if searchMode {
                searchField(matches: matches)
                Button("Cancel", action: endSearch).buttonStyle(.text).padding(.leading, 8)
            } else {
                tabs
                IconButton(title: "Search · ⌘F", icon: "magnifyingglass", action: beginSearch)
                moreMenu
            }
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.top, 4)
        .frame(height: AppDefaults.CaptureItem.panelHeaderHeight)
    }

    /// The first sections as tabs, then a menu tab with every section and Done.
    /// The menu tab names the active section when no other tab shows it.
    private var tabs: some View {
        let shown = Array(store.sections.prefix(AppDefaults.CaptureItem.sectionTabCount))
        let otherActive = content == .sections && !shown.contains(store.activeSection)
        return HStack(spacing: 2) {
            ForEach(shown, id: \.self) { section in
                PanelTab(title: section, icon: nil, count: openCount(section),
                         active: content == .sections && store.activeSection == section) {
                    showSection(section)
                }
            }
            PanelTab(title: content == .archived ? "Done" : otherActive ? store.activeSection : "More",
                     icon: nil, count: 0, active: content == .archived || otherActive, opensMenu: true) {
                showingSections = true
            }
            .accessibilityLabel("Choose Section")
            .popover(isPresented: $showingSections, arrowEdge: .bottom) {
                CaptureSectionMenu(sections: store.sections, current: content == .sections ? store.activeSection : nil,
                                   done: content == .archived, count: openCount,
                                   doneCount: store.notes.filter { $0.parent == nil && $0.isDone }.count,
                                   choose: { section in
                                       showingSections = false
                                       showSection(section)
                                   }, showDone: {
                                       showingSections = false
                                       panelContent = .archived
                                       composing = false
                                   }, newSection: {
                                       showingSections = false
                                       sheet = .newSection
                                   })
            }
        }
        .padding(2)
        .background(PiperTheme.tabTrack, in: RoundedRectangle(cornerRadius: PiperTheme.radius + 2, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func showSection(_ section: String) {
        panelContent = .sections
        chooseSection(section)
        composing = true
    }

    private var moreMenu: some View {
        Menu {
            Button("Capture Clipboard", systemImage: "doc.on.clipboard") { store.captureClipboard() }
            Button("Capture To…", systemImage: "tray") { sheet = .sections(moving: false) }
            Button("New Section…", systemImage: "plus") { sheet = .newSection }
            Divider()
            Button("Open Main Window", systemImage: "macwindow") { model.openLibrary?() }
            Button("Settings…", systemImage: "gearshape") { model.openSettings?() }
            Divider()
            Button("Undo Last Change", systemImage: "arrow.uturn.backward") { store.undo() }.disabled(!store.canUndo)
            Button("Close Capture") { (NSApp.keyWindow as? CapturePanel)?.orderOut(nil) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(PiperTheme.secondary)
                .frame(width: 28, height: 24).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .tint(PiperTheme.secondary)
        .help("More Actions").accessibilityLabel("More Actions")
    }

    /// The search field over the Inbox list in the main window. The window
    /// title names the list.
    private func paneHeader(_ stream: InboxStream?, matches: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let stream { filterChips(stream.counts) }
            searchField(matches: matches)
        }
        .padding(.horizontal, AppDefaults.ListSearch.horizontalInset)
        .padding(.vertical, AppDefaults.ListSearch.verticalInset)
    }

    /// All, Notes, and Reading, with the number of captures in each.
    private func filterChips(_ counts: [InboxStream.Filter: Int]) -> some View {
        HStack(spacing: 6) {
            ForEach(InboxStream.Filter.allCases, id: \.self) { item in
                FilterChip(title: item.title, count: counts[item] ?? 0, active: item == filter) { setFilter(item) }
            }
        }
    }

    private func searchField(matches: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(PiperTheme.faint)
            TextField("Search", text: $store.query)
                .textFieldStyle(.plain).focused($searching)
                .font(PiperTheme.ui(.body))
                .accessibilityLabel(content == .clipboard ? "Search the clipboard" : "Search notes")
                .onAppear {
                    if showingSearch { DispatchQueue.main.async { searching = true } }
                }
            if searchMode {
                let matches = content == .clipboard ? clipboardEntries.count : matches + recentClipboard.count
                Text(count(matches, "match", "matches"))
                    .font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.faint).lineLimit(1).fixedSize()
            }
            if embedded && !store.query.isEmpty {
                Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PiperTheme.faint) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: embedded ? 22 : 26)
        .background(PiperTheme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: embedded ? PiperTheme.radius : 8))
        .overlay {
            RoundedRectangle(cornerRadius: embedded ? PiperTheme.radius : 8)
                .strokeBorder(searching ? PiperTheme.focusRing : .clear, lineWidth: 3)
                .padding(-2)
        }
        .frame(maxWidth: .infinity)
    }

    private var accessibilityTip: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(PiperTheme.accent)
            (Text("Capture from other apps. ").foregroundStyle(PiperTheme.ink).fontWeight(.medium)
                + Text("Enable Accessibility to save a selection with \(shortcutGlyphs)."))
                .font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Enable") { model.requestAccessibility() }.buttonStyle(.text)
            Button { tipDismissed = true } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(PiperTheme.faint)
                    .frame(width: 16, height: 16).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Hide").accessibilityLabel("Hide this tip")
        }
        .padding(.vertical, 7).padding(.leading, 10).padding(.trailing, 8)
        .background(PiperTheme.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
        .padding(.horizontal, AppDefaults.CaptureItem.listInset).padding(.bottom, 6)
    }

    // MARK: Lists

    private var sectionList: some View {
        let doneToday = searchMode ? [] : InboxStream.doneToday(notes: store.notes, section: store.activeSection)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !searchMode { BriefGroup(model: model) }
                    if !recentClipboard.isEmpty {
                        SectionHeader(title: "Clipboard", detail: nil, active: false, action: nil)
                        CaptureCard {
                            ForEach(Array(recentClipboard.enumerated()), id: \.element.id) { index, entry in
                                clipboardRow(entry, showsSource: false, separated: index > 0)
                            }
                        }
                    }
                    ForEach(displayedSections, id: \.self) { section in
                        let notes = panelNotes(in: section)
                        if searchMode {
                            SectionHeader(title: section, detail: "\(notes.count)", active: false, action: nil)
                        }
                        if notes.isEmpty && doneToday.isEmpty {
                            Text("No notes in \(section)")
                                .font(PiperTheme.ui(.body)).foregroundStyle(PiperTheme.faint)
                                .padding(.horizontal, AppDefaults.CaptureItem.horizontalPadding)
                                .frame(maxWidth: .infinity, minHeight: AppDefaults.CaptureItem.minimumHeight, alignment: .leading)
                        }
                        ForEach(notes) { note in
                            noteRow(note).id(note.id)
                            if showsChildren(note.id, byDefault: true) {
                                ForEach(store.children(of: note.id)) { child in
                                    childRow(child, of: note)
                                }
                            }
                        }
                    }
                    if !doneToday.isEmpty {
                        DoneTodayHeader(count: doneToday.count, shown: showsDoneToday) { showsDoneToday.toggle() }
                        if showsDoneToday {
                            ForEach(doneToday) { note in noteRow(note).id(note.id) }
                        }
                    }
                }
                .padding(.horizontal, AppDefaults.CaptureItem.listInset)
                .padding(.bottom, 12)
            }
            .overlay {
                if searchMode && matchingNotes.isEmpty && recentClipboard.isEmpty && !store.query.isEmpty {
                    EmptyPane(title: "No Results", detail: "Try another word.")
                }
            }
            .onChange(of: store.notes.count) { oldCount, newCount in
                if newCount > oldCount, let note = store.notes.last {
                    withAnimation(motion) { proxy.scrollTo(note.id, anchor: .top) }
                }
            }
            .onChange(of: selectionAnchor) { _, id in
                if let id { withAnimation(motion) { proxy.scrollTo(id) } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The latest clipboard texts, under the list of the panel. The strip folds,
    /// and See All shows the whole clipboard history.
    @ViewBuilder private var clipboardStrip: some View {
        let entries = Array(model.clipboard.entries.prefix(AppDefaults.CaptureItem.recentClipboardCount))
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button { withAnimation(motion) { clipboardFolded.toggle() } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: clipboardFolded ? "chevron.right" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Clipboard").fontWeight(.semibold).foregroundStyle(PiperTheme.ink)
                            Text("· \(entries.count) latest")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(clipboardFolded ? "Show Clipboard" : "Hide Clipboard")
                    Spacer(minLength: 4)
                    Button("See All") {
                        panelContent = .clipboard
                        composing = false
                    }
                    .buttonStyle(.text)
                }
                .font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary)
                .padding(.horizontal, 6)
                if !clipboardFolded {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            ClipboardRow(entry: entry, showsSource: false, separated: false,
                                         paste: { paste(entry) }, keep: { keep(entry) }, read: readAction(entry),
                                         agents: agents, send: { send(entry, $0) }, compact: true)
                        }
                    }
                }
            }
            .padding(.horizontal, AppDefaults.CaptureItem.listInset)
            .padding(.vertical, 8)
            .background(PiperTheme.ink.opacity(0.025))
            .overlay(alignment: .top) { Rule() }
        }
    }

    private func clipboardRow(_ entry: ClipboardEntry, showsSource: Bool, separated: Bool) -> some View {
        ClipboardRow(entry: entry, showsSource: showsSource, separated: separated,
                     paste: { paste(entry) }, keep: { keep(entry) }, read: readAction(entry),
                     agents: agents, send: { send(entry, $0) })
    }

    /// The Inbox of the main window: Continue Reading, one group for each day,
    /// and the captures done today.
    private func streamList(_ stream: InboxStream) -> some View {
        let showsBrief = content == .stream(section: nil) && filter == .all && store.query.isEmpty
        let doneToday = filter == .reading || !store.query.isEmpty ? []
            : InboxStream.doneToday(notes: store.notes, section: streamSection).filter { filter == .all || !$0.isArticle }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if showsBrief { BriefGroup(model: model) }
                    ForEach(stream.groups, id: \.title) { group in
                        StreamHeader(title: group.title,
                                     action: group.kind == .started && filter == .all ? ("See All", { setFilter(.reading) }) : nil)
                        ForEach(Array(group.notes.enumerated()), id: \.element.id) { index, note in
                            inboxRow(note, style: rowStyle(note, in: group, at: index)).id(note.id)
                            if showsChildren(note.id, byDefault: false) {
                                ForEach(store.children(of: note.id)) { child in
                                    childRow(child, of: note)
                                }
                            }
                        }
                    }
                    if !doneToday.isEmpty {
                        DoneTodayHeader(count: doneToday.count, shown: showsDoneToday) { showsDoneToday.toggle() }
                        if showsDoneToday {
                            ForEach(doneToday) { note in
                                inboxRow(note, style: note.isArticle ? .compact : .note).id(note.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .overlay {
                if stream.groups.isEmpty && doneToday.isEmpty && !(showsBrief && BriefGroup.shows(model.brief)) {
                    if !store.query.isEmpty {
                        EmptyPane(title: "No Results", detail: "Try another word.")
                    } else if filter == .reading {
                        EmptyPane(title: "Nothing to Read", detail: "On a web page, press Shift twice to save it here.")
                    } else {
                        EmptyPane(title: "No Notes", detail: "Type a note above, or press Shift twice in another app.")
                    }
                }
            }
            .onChange(of: selectionAnchor) { _, id in
                if let id { withAnimation(motion) { proxy.scrollTo(id) } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The done captures, one group for each month. The main window uses the
    /// rows of the Inbox stream, and the panel uses its cards.
    private var archiveList: some View {
        let groups = archiveGroups
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.title) { group in
                        if embedded {
                            StreamHeader(title: group.title, action: nil)
                            ForEach(group.notes) { note in
                                inboxRow(note, style: note.isArticle ? .compact : .note).id(note.id)
                            }
                        } else {
                            SectionHeader(title: group.title, detail: "\(group.notes.count)", active: false, action: nil)
                            ForEach(group.notes) { note in noteRow(note).id(note.id) }
                        }
                    }
                }
                .padding(.horizontal, embedded ? 8 : AppDefaults.CaptureItem.listInset)
                .padding(.bottom, 12)
            }
            .overlay {
                if groups.isEmpty {
                    if store.query.isEmpty {
                        EmptyPane(title: "No Done Notes", detail: "Notes that you mark as done show here.")
                    } else {
                        EmptyPane(title: "No Results", detail: "Try another word.")
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
            section: streamSection == nil && note.section != SidebarOutline.inboxSection
                ? (note.section, sectionColor(note.section)) : nil,
            children: store.children(of: note.id),
            showsChildren: showsChildren(note.id, byDefault: false),
            toggleChildren: { toggleChildren(note.id) },
            session: session,
            select: { openNote(note.id) },
            complete: { note.isDone || style == .note ? store.toggleDone(note.id) : toggleRead(note) },
            openRun: { openRun(for: note) },
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

    /// The dot color of a section, as the sidebar shows it.
    private func sectionColor(_ section: String) -> Color {
        let position = store.sections.filter { $0 != SidebarOutline.inboxSection }.firstIndex(of: section) ?? 0
        return Color(nsColor: SidebarOutline.tagColor(at: position))
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

    private var clipboardHistory: some View {
        let days = Dictionary(grouping: clipboardEntries) { Calendar.current.startOfDay(for: $0.copiedAt) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    let entries = days[day] ?? []
                    DayHeader(title: Self.dayTitle(day))
                    CaptureCard {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            clipboardRow(entry, showsSource: true, separated: index > 0)
                        }
                    }
                }
                if !clipboardEntries.isEmpty && store.query.isEmpty {
                    Button("Clear History") { withAnimation(motion) { model.clipboard.clear() } }
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, AppDefaults.CaptureItem.listInset)
            .padding(.bottom, 12)
        }
        .overlay {
            if clipboardEntries.isEmpty {
                if store.query.isEmpty {
                    EmptyPane(title: "No Copies", detail: "Text you copy appears here for 7 days.")
                } else {
                    EmptyPane(title: "No Results", detail: "Try another word.")
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func childRow(_ child: Note, of parent: Note) -> some View {
        ChildNoteRow(note: child,
                     open: {
                         if store.selection != [parent.id] { embedded ? openNote(parent.id) : selectNote(parent.id) }
                         model.showHighlight(child.id, in: parent.id)
                     },
                     openNote: {
                         if embedded { model.showNote?(child.id) } else { sheet = .edit(model.editCapture(child)) }
                     },
                     addTag: {
                         tagText = ""
                         taggedNote = child.id
                     },
                     copy: { store.copy(child.id) },
                     delete: { store.delete(child.id) })
    }

    private func noteRow(_ note: Note) -> some View {
        NoteRow(note: note, selected: store.selection.contains(note.id),
                select: { selectNote(note.id) },
                complete: { store.toggleDone(note.id) },
                edit: { sheet = .edit(model.editCapture(note)) },
                newWindow: { model.openNoteEditor?(note) },
                copy: { asList in
                    if !store.selection.contains(note.id) { store.selection = [note.id] }
                    store.copy(asList: asList)
                },
                prepareActions: {
                    if !store.selection.contains(note.id) { store.selection = [note.id] }
                },
                merge: { store.merge() },
                move: { sheet = .sections(moving: true) },
                delete: {
                    if !store.selection.contains(note.id) { store.selection = [note.id] }
                    store.deleteSelection()
                },
                canMerge: store.selection.contains(note.id) && store.selection.count > 1,
                session: agents.latestSession(for: note),
                agents: agents,
                send: { action in agents.send(note, action: action) },
                openRun: { openRun(for: note) },
                stopRun: { if let session = agents.latestSession(for: note) { agents.runner.stop(session) } },
                childCount: store.children(of: note.id).count,
                showsChildren: showsChildren(note.id, byDefault: true),
                toggleChildren: { toggleChildren(note.id) })
    }

    // MARK: Selection, composer, hints

    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: AppDefaults.CaptureItem.actionSpacing) {
            HStack {
                Text("\(store.selection.count) selected").font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary)
                Spacer()
                if embedded { Button("Cancel") { clearSelection() }.buttonStyle(.text).help("Clear the selection · Escape") }
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
        .padding(.horizontal, embedded ? AppDefaults.ListSearch.horizontalInset : AppDefaults.CaptureItem.listInset + 2)
        .padding(.vertical, AppDefaults.CaptureItem.actionSpacing)
        .overlay(alignment: .top) { if embedded { Rule() } }
    }

    /// The add field: one line that grows with its text, up to `Composer.maxLines`.
    private var composer: some View {
        let metrics = AppDefaults.Composer.self
        let inset = metrics.textInset.height * 2
        let text = min(max(composerTextHeight, metrics.inboxLineHeight + inset),
                       metrics.inboxLineHeight * CGFloat(metrics.maxLines) + inset)
        return HStack(alignment: .top, spacing: 0) {
            Circle()
                .strokeBorder(PiperTheme.faint, style: StrokeStyle(lineWidth: AppDefaults.ProgressRing.lineWidth, dash: [2.5, 2.5]))
                .frame(width: AppDefaults.CaptureItem.circleSize, height: AppDefaults.CaptureItem.circleSize)
                .padding(.top, metrics.regionInset + metrics.textInset.height)
                .accessibilityHidden(true)
            CaptureEditor(text: $model.composerDraft, focused: $composing,
                          placeholder: "Add to \(store.activeSection)", compact: true,
                          contentHeight: { composerTextHeight = $0 })
                .frame(height: text + metrics.regionInset * 2)
            if embedded && composing {
                Text(inboxHint)
                    .font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.faint)
                    .lineLimit(1).help(inboxHint)
                    .padding(.trailing, 10)
                    .padding(.top, metrics.regionInset + metrics.textInset.height + 2)
                    .allowsHitTesting(false)
            }
        }
        .padding(.leading, AppDefaults.CaptureItem.horizontalPadding - 2)
        .background(PiperTheme.card, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
        .background {
            RoundedRectangle(cornerRadius: PiperTheme.cardRadius + 3.5)
                .fill(composing ? PiperTheme.focusRing : .clear)
                .padding(-3.5)
        }
        .padding(.horizontal, AppDefaults.Composer.margin)
        .padding(.top, 4)
        .padding(.bottom, 8)
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

    private var hints: some View {
        HStack(spacing: 6) {
            if composing, let action = composedAction {
                Text("Return runs /\(action.skill.name) in \(action.folder.name)")
            } else if !completions.isEmpty {
                Text("Tab completes · ↑↓ choose")
            } else if store.status == "Local notes" || content == .clipboard {
                Text(content == .clipboard
                     ? "Not saved as notes. Texts leave after 7 days."
                     : "↩ adds to \(store.activeSection) · ⌘K section")
            } else {
                Text(store.status).help(store.status)
            }
            Spacer(minLength: 4)
            if store.canUndo && content != .clipboard {
                Button("Undo") { store.undo() }.buttonStyle(.text).font(PiperTheme.ui(.caption)).help("Undo Last Change")
            } else {
                Text("\(shortcutGlyphs) captures a selection")
                    .accessibilityLabel("\(model.captureShortcut) captures selected text")
            }
        }
        .lineLimit(1)
        .font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.faint)
        .padding(.horizontal, AppDefaults.CaptureItem.listInset + 4)
        .frame(height: 30)
        .padding(.bottom, AppDefaults.CaptureItem.hintBottomPadding)
    }

    // MARK: Values

    private var shortcutGlyphs: String {
        model.captureShortcut == "Shift, Shift" ? "⇧⇧" : "⌃⌥Space"
    }

    /// True when the list shows the child notes of a capture. The panel
    /// shows them by default, and the Inbox stream hides them by default.
    private func showsChildren(_ id: UUID, byDefault shown: Bool) -> Bool {
        toggledParents.contains(id) != shown
    }

    private func toggleChildren(_ id: UUID) {
        if toggledParents.contains(id) { toggledParents.remove(id) } else { toggledParents.insert(id) }
    }

    private func openCount(_ section: String) -> Int {
        store.notes.filter { $0.section == section && !$0.isDone }.count
    }

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

    /// Sends a clipboard entry to the application the reader came from.
    ///
    /// The panel goes off the screen first, because the paste arrives in
    /// whichever application is in front.
    private func paste(_ entry: ClipboardEntry) {
        (NSApp.keyWindow as? CapturePanel)?.orderOut(nil)
        if !ClipboardPaster.paste(entry.text) { store.status = "Copied. Press Command-V to paste it." }
    }

    /// Saves a copied web link to Reading and opens it in the main window.
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
        } else if embedded {
            store.selection = [note.id]
            selectionAnchor = note.id
        } else {
            model.showNote?(note.id)
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

    /// Opens one capture in the detail pane, and ends a selection of several.
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
            guard !showingSections, let window = NSApp.keyWindow, window.attachedSheet == nil,
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
                else if !embedded { window.orderOut(nil) }
                else { return event }
                return nil
            }
            if event.keyCode == 36, !flags.contains(.shift), !flags.contains(.option), !flags.contains(.control) {
                if composing { saveNote(); return nil }
                if !editingText, let note = store.selectedNotes.first {
                    if flags.contains(.command) { model.openNoteEditor?(note) }
                    else { sheet = .edit(model.editCapture(note)) }
                    return nil
                }
            }
            if !editingText, !flags.contains(.command), !flags.contains(.option), !flags.contains(.control) {
                if [51, 117].contains(event.keyCode), !store.selection.isEmpty { store.deleteSelection(); return nil }
                if event.keyCode == 49, !store.selection.isEmpty { store.completeSelection(); return nil }
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
            case "n" where !embedded: store.selection.removeAll(); panelContent = .sections; composing = true
            case "a" where !editingText: store.selection = Set(matchingNotes.map(\.id)); checking = true
            case "c" where !editingText && !store.selection.isEmpty: store.copy(asList: flags.contains(.shift))
            case "m" where flags.contains(.shift) && !editingText: store.merge()
            case "z" where !editingText: store.undo()
            case "w" where !embedded: window.orderOut(nil)
            default: return event
            }
            return nil
        }
    }
}

/// One chip over the Inbox stream.
private struct FilterChip: View {
    let title: String
    let count: Int
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppDefaults.FilterChip.spacing) {
                Text(title).fontWeight(active ? .medium : .regular)
                Text("\(count)").font(PiperTheme.ui(AppDefaults.FilterChip.countFontSize))
                    .opacity(AppDefaults.FilterChip.countOpacity).monospacedDigit()
            }
            .font(PiperTheme.ui(AppDefaults.FilterChip.fontSize))
            .foregroundStyle(active ? PiperTheme.page : PiperTheme.secondary)
            .padding(.horizontal, AppDefaults.FilterChip.horizontalPadding)
            .frame(height: AppDefaults.FilterChip.height)
            .background(active ? PiperTheme.ink : PiperTheme.hover, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

/// The fold over the captures done today, at the end of a list.
private struct DoneTodayHeader: View {
    let count: Int
    let shown: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: shown ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                Text("\(count) done today")
                Spacer(minLength: 0)
            }
            .font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 10).padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rule().padding(.horizontal, 4) }
        .padding(.top, 8)
        .accessibilityLabel(shown ? "Hide \(count) done today" : "Show \(count) done today")
    }
}

/// The header of one group of the Inbox stream, such as Today.
private struct StreamHeader: View {
    let title: String
    let action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(PiperTheme.ui(.caption, weight: .semibold)).foregroundStyle(PiperTheme.faint)
            Spacer(minLength: 4)
            if let action { Button(action.0, action: action.1).buttonStyle(.text).font(PiperTheme.ui(.caption)) }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12).padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}
