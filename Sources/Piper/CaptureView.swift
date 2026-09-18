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
    /// Every section in one list. The panel also shows the latest clipboard texts.
    case sections
    /// The whole clipboard history, grouped by day.
    case clipboard
}

/// A request to scroll the list to a section. A new identity scrolls again.
struct SectionScroll: Equatable {
    let section: String
    let id = UUID()
}

/// The capture list, in the capture panel and in the Inbox pane of the main window.
///
/// One list holds every section under its own header. The panel header holds a
/// tab for each section, and a tab scrolls the list to its header. The main
/// window does the same from the children of Inbox in the sidebar.
struct CaptureView: View {
    @Bindable var store: CaptureStore
    @Bindable var model: AppModel
    let embedded: Bool
    let acceptsKeyboard: (NSWindow) -> Bool
    let focusNotes: () -> Void
    let selectCapture: (UUID?) -> Void
    /// What the main window shows. The panel keeps its own tab.
    let embeddedContent: CaptureListContent
    /// The section that the sidebar selected in the main window.
    let embeddedScroll: SectionScroll?

    init(model: AppModel, embedded: Bool = false,
         content: CaptureListContent = .sections,
         scroll: SectionScroll? = nil,
         acceptsKeyboard: @escaping (NSWindow) -> Bool = { $0 is CapturePanel },
         focusNotes: @escaping () -> Void = {},
         selectCapture: @escaping (UUID?) -> Void = { _ in }) {
        self.embedded = embedded
        self.embeddedContent = content
        self.embeddedScroll = scroll
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
    @FocusState private var searching: Bool
    @State private var composing = false
    @State private var panelContent = CaptureListContent.sections
    @State private var scroll: SectionScroll?
    /// The highlighted row of the skill list over the composer.
    @State private var completionIndex = 0
    /// The skill the reader picked from the list, which also picks the folder.
    @State private var chosenAction: FolderAgents.Action?
    @AppStorage(AppDefaults.Key.accessibilityTipDismissed) private var tipDismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var content: CaptureListContent { embedded ? embeddedContent : panelContent }
    private var searchMode: Bool { showingSearch || !store.query.isEmpty }
    private var displayedSections: [String] {
        searchMode ? store.sections.filter { !store.visibleNotes(in: $0).isEmpty } : store.sections
    }
    private var matchingNotes: [Note] {
        content == .clipboard ? [] : displayedSections.flatMap { store.visibleNotes(in: $0) }
    }
    private var clipboardEntries: [ClipboardEntry] {
        model.clipboard.entries.filter {
            store.query.isEmpty || $0.text.localizedCaseInsensitiveContains(store.query)
        }
    }
    /// The clipboard texts at the top of the section list.
    private var recentClipboard: [ClipboardEntry] {
        guard !embedded else { return [] }
        return searchMode ? clipboardEntries : Array(clipboardEntries.prefix(AppDefaults.CaptureItem.recentClipboardCount))
    }
    private var showsComposer: Bool { !embedded && content == .sections }
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
        VStack(spacing: 0) {
            if embedded { paneHeader } else { panelHeader }
            if !embedded && !model.accessibilityEnabled && !tipDismissed { accessibilityTip }
            switch content {
            case .sections:
                sectionList.overlay(alignment: .bottom) { skillList }
            case .clipboard: clipboardHistory
            }
            if !store.selection.isEmpty { selectionBar }
            if showsComposer { composer }
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
                        store.status = "Capturing to \(store.activeSection)"
                        scrollTo(store.activeSection)
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
        .onChange(of: content) { _, _ in clearSelection() }
        .onChange(of: store.selection) { _, selection in
            selectCapture(selection.count == 1 ? selection.first : nil)
        }
        .onChange(of: embeddedScroll, initial: true) { _, request in
            if embedded { scroll = request }
        }
        .onChange(of: model.composerDraft) { _, _ in completionIndex = 0 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard !embedded, let window = notification.object as? CapturePanel, window.attachedSheet == nil else { return }
            agents.refresh(paths: model.wikiPaths)
            if store.selection.isEmpty && !searchMode && content == .sections { composing = true }
        }
        .onAppear {
            composing = showsComposer
            installKeyboardShortcuts()
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    // MARK: Headers

    private var panelHeader: some View {
        HStack(spacing: 2) {
            if searchMode {
                searchField
                Button("Cancel", action: endSearch).buttonStyle(.text).padding(.leading, 8)
            } else {
                tabs
                IconButton(title: "Search · ⌘F", icon: "magnifyingglass", action: beginSearch)
                moreMenu
            }
        }
        .padding(.leading, 12).padding(.trailing, 8)
        .frame(height: 46)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                PanelTab(title: "Clipboard", icon: "doc.on.clipboard", count: 0, active: content == .clipboard) {
                    panelContent = .clipboard
                    composing = false
                }
                Rectangle().fill(PiperTheme.rule).frame(width: 1, height: 16).padding(.horizontal, 4)
                ForEach(store.sections, id: \.self) { section in
                    PanelTab(title: section, icon: nil, count: openCount(section),
                             active: content == .sections && section == store.activeSection) {
                        panelContent = .sections
                        chooseSection(section)
                        composing = true
                    }
                }
                Button { sheet = .newSection } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PiperTheme.secondary)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("New Section").accessibilityLabel("New Section")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    private var paneHeader: some View {
        searchField
            .padding(.horizontal, AppDefaults.ListSearch.horizontalInset)
            .padding(.vertical, AppDefaults.ListSearch.verticalInset)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(PiperTheme.faint)
            TextField("Search", text: $store.query)
                .textFieldStyle(.plain).focused($searching)
                .font(PiperTheme.ui(13))
                .accessibilityLabel(content == .clipboard ? "Search the clipboard" : "Search notes")
                .onAppear {
                    if showingSearch { DispatchQueue.main.async { searching = true } }
                }
            if searchMode {
                let matches = content == .clipboard ? clipboardEntries.count : matchingNotes.count + recentClipboard.count
                Text(count(matches, "match", "matches"))
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint).lineLimit(1).fixedSize()
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
                .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !recentClipboard.isEmpty {
                        SectionHeader(title: "Clipboard",
                                      detail: searchMode ? nil : "\(recentClipboard.count) latest",
                                      active: false,
                                      action: searchMode ? nil : ("See All", { panelContent = .clipboard }))
                        CaptureCard {
                            ForEach(Array(recentClipboard.enumerated()), id: \.element.id) { index, entry in
                                ClipboardRow(entry: entry, showsSource: false, separated: index > 0,
                                             paste: { paste(entry) }, keep: { keep(entry) },
                                             agents: agents, send: { send(entry, $0) })
                            }
                        }
                    }
                    ForEach(displayedSections, id: \.self) { section in
                        let notes = store.visibleNotes(in: section)
                        SectionHeader(title: section, detail: openCount(section) > 0 ? "\(openCount(section))" : nil,
                                      active: !embedded && !searchMode && section == store.activeSection, action: nil)
                            .id(Self.anchor(section))
                        CaptureCard {
                            if notes.isEmpty {
                                Text("No notes in \(section)")
                                    .font(PiperTheme.ui(13)).foregroundStyle(PiperTheme.faint)
                                    .padding(.horizontal, AppDefaults.CaptureItem.horizontalPadding)
                                    .frame(maxWidth: .infinity, minHeight: AppDefaults.CaptureItem.clipboardHeight, alignment: .leading)
                            }
                            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                                noteRow(note, separated: index > 0).id(note.id)
                            }
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
                    withAnimation(motion) { proxy.scrollTo(note.id, anchor: .bottom) }
                }
            }
            .onChange(of: selectionAnchor) { _, id in
                if let id { withAnimation(motion) { proxy.scrollTo(id) } }
            }
            .onChange(of: scroll, initial: true) { _, request in
                guard let request else { return }
                DispatchQueue.main.async {
                    withAnimation(motion) { proxy.scrollTo(Self.anchor(request.section), anchor: .top) }
                }
            }
        }
        .frame(maxHeight: .infinity)
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
                            ClipboardRow(entry: entry, showsSource: true, separated: index > 0,
                                         paste: { paste(entry) }, keep: { keep(entry) },
                                         agents: agents, send: { send(entry, $0) })
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

    private func noteRow(_ note: Note, separated: Bool) -> some View {
        NoteRow(note: note, selected: store.selection.contains(note.id), separated: separated,
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
                stopRun: { if let session = agents.latestSession(for: note) { agents.runner.stop(session) } })
    }

    // MARK: Selection, composer, hints

    private var selectionBar: some View {
        HStack(spacing: 6) {
            Text("\(store.selection.count) selected").font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
            Spacer(minLength: 0)
            if !agents.folders.isEmpty {
                SendButton(agents: agents, title: "Send", sendDefault: { agents.sendSelection() },
                           send: { agents.sendSelection(action: $0) })
                    .help("Send each note with its default skill · ⇧⌘Return")
            }
            Button("Merge") { store.merge() }
                .disabled(store.selection.count < 2).help("Merge Notes · ⇧⌘M")
            Button("Move…") { sheet = .sections(moving: true) }
            Button("Copy") { store.copy(asList: false) }.help("Copy · ⌘C. Copy as List · ⇧⌘C")
            Button("Delete") { store.deleteSelection() }.help("Delete Notes · Delete")
        }
        .controlSize(.small)
        .padding(.horizontal, embedded ? AppDefaults.ListSearch.horizontalInset : AppDefaults.CaptureItem.listInset + 2)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { if embedded { Rule() } }
    }

    private var composer: some View {
        HStack(alignment: .top, spacing: 0) {
            Circle()
                .strokeBorder(PiperTheme.faint, lineWidth: 1.25)
                .frame(width: AppDefaults.CaptureItem.circleSize, height: AppDefaults.CaptureItem.circleSize)
                .padding(.top, AppDefaults.Composer.regionInset + AppDefaults.Composer.textInset.height + 3)
                .accessibilityHidden(true)
            CaptureEditor(text: $model.composerDraft, focused: $composing,
                          placeholder: "New note in \(store.activeSection)")
                .frame(height: AppDefaults.Composer.height)
        }
        .padding(.leading, AppDefaults.CaptureItem.horizontalPadding)
        .background(PiperTheme.card, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
        .background {
            RoundedRectangle(cornerRadius: PiperTheme.cardRadius + 3.5)
                .fill(composing ? PiperTheme.focusRing : .clear)
                .padding(-3.5)
        }
        .padding(.horizontal, AppDefaults.Composer.margin)
        .padding(.top, store.selection.isEmpty ? 8 : 0)
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
                     : "Return saves to \(store.activeSection) · ⌘K section")
            } else {
                Text(store.status).help(store.status)
            }
            Spacer(minLength: 4)
            if store.canUndo && content == .sections {
                Button("Undo") { store.undo() }.buttonStyle(.text).font(PiperTheme.ui(11)).help("Undo Last Change")
            } else {
                Text("\(shortcutGlyphs) captures a selection")
                    .accessibilityLabel("\(model.captureShortcut) captures selected text")
            }
        }
        .lineLimit(1)
        .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint)
        .padding(.horizontal, AppDefaults.CaptureItem.listInset + 4)
        .frame(height: 30)
        .padding(.bottom, AppDefaults.CaptureItem.hintBottomPadding)
    }

    // MARK: Values

    private var shortcutGlyphs: String {
        model.captureShortcut == "Shift, Shift" ? "⇧⇧" : "⌃⌥Space"
    }

    private func openCount(_ section: String) -> Int {
        store.notes.filter { $0.section == section && !$0.isDone }.count
    }

    private func count(_ value: Int, _ one: String, _ many: String) -> String {
        "\(value) \(value == 1 ? one : many)"
    }

    static func anchor(_ section: String) -> String { "section:" + section }

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
        if section != store.activeSection {
            clearSelection()
            guard store.chooseSection(section) else { return }
        }
        scrollTo(section)
    }

    private func scrollTo(_ section: String) {
        scroll = SectionScroll(section: section)
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

    private func selectNote(_ id: UUID) {
        composing = false
        showingSearch = searchMode && !store.query.isEmpty
        searching = false
        focusNotes()
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = selectionAnchor,
           let start = matchingNotes.firstIndex(where: { $0.id == anchor }),
           let end = matchingNotes.firstIndex(where: { $0.id == id }) {
            store.selection.formUnion(matchingNotes[min(start, end)...max(start, end)].map(\.id))
        } else if flags.contains(.command) {
            store.toggleSelection(id)
            selectionAnchor = id
        } else {
            store.selection = [id]
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
            if createsSection {
                store.status = "Capturing to \(store.activeSection)"
                scrollTo(store.activeSection)
            }
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
            guard let window = NSApp.keyWindow, window.attachedSheet == nil,
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
                    if flags.contains(.shift) { store.selection.insert(id) }
                    else { store.selection = [id] }
                    selectionAnchor = id
                    return nil
                }
            }
            guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "k": sheet = .sections(moving: false)
            case "f": beginSearch()
            case "n" where !embedded: store.selection.removeAll(); panelContent = .sections; composing = true
            case "a" where !editingText: store.selection = Set(matchingNotes.map(\.id))
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
