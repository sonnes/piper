import AppKit
import Agents
import Captures
import Feeds
import PiperCore
import Stream
import SwiftUI

/// What the capture field holds: a note, a web link to read later, or the
/// address of a feed or a site, which the Sources paper subscribes to.
enum CaptureDraft: Equatable {
    case note
    case link(URL)
    case source(URL)

    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace), let url = CaptureLinks(trimmed).standaloneURL,
              url.isWeb else {
            self = .note
            return
        }
        self = Self.isSource(url) ? .source(url) : .link(url)
    }

    /// True for the address of a site, with no path, or of a feed.
    static func isSource(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.isEmpty || path == "/" { return url.query == nil }
        let name = (path as NSString).lastPathComponent
        return ["xml", "rss", "atom", "rdf"].contains((name as NSString).pathExtension)
            || ["feed", "rss", "atom", "feed.json", "index.xml"].contains(name)
    }
}

/// Today on the feed paper: the capture field, the lenses, the stream in
/// groups, and the clipboard tray at the foot.
///
/// A click selects a row, and Return or a second click opens it as a reader
/// paper. Command-click and Shift-click select several rows, and a floating
/// bar shows their verbs.
struct TodayView: View {
    @Bindable var today: TodayModel
    @Bindable var paper: FeedPaperModel
    @Bindable var model: AppModel
    /// The window of the paper, for the keyboard focus.
    let window: () -> NSWindow?

    @State private var keyMonitor: Any?
    @State private var showingSearch = false
    @FocusState private var searching: Bool
    @State private var composing = false
    @State private var composerTextHeight: CGFloat = 0
    @State private var completionIndex = 0
    @State private var chosenAction: FolderAgents.Action?
    @State private var showsDoneToday = false
    @State private var showsWholeTray = false
    @State private var editing: CaptureEditSession?
    @Environment(\.paperDesk) private var desk
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: CaptureStore { model.store }
    private var agents: FolderAgents { model.agents }
    private var scope: PaperScope { paper.state.scope }
    private var section: String? {
        if case .today(let section) = scope { return section }
        return nil
    }
    private var isDone: Bool { scope == .done }
    private var searchMode: Bool { showingSearch || !today.query.isEmpty }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }
    private var canSave: Bool { !model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The skills that match the command in the composer.
    private var completions: [FolderAgents.Action] {
        guard composing, let partial = SlashCommand.partialName(model.composerDraft) else { return [] }
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
        let stream = isDone ? nil : UnifiedStream(today.input(), lens: paper.state.lens, section: section, query: today.query)
        let groups = stream?.groups ?? UnifiedStream.done(notes: store.notes, query: today.query)
        let tray = stream?.tray ?? []
        let order = Self.order(groups, tray)
        let items = Self.index(groups, tray)
        VStack(spacing: 0) {
            if searchMode { searchField(matches: groups.flatMap(\.items).count) }
            if !isDone { composer }
            if let stream { lenses(stream.counts) }
            list(groups, items: items, order: order)
                .overlay(alignment: .bottom) { skillList }
                .overlay(alignment: .bottom) { floating(items: items, order: order) }
            if !tray.isEmpty { trayView(tray, items: items, order: order) }
        }
        .background(PiperTheme.paper)
        .sheet(item: $editing) { session in
            NoteEditor(model: model, session: session) {
                if model.saveCaptureEdit(session) { editing = nil }
            }
        }
        .sheet(isPresented: Binding(get: { !today.filing.isEmpty }, set: { if !$0 { today.filing = [] } })) {
            FilePicker(today: today, items: today.filing)
        }
        .onChange(of: order) { _, order in today.keepSelection(in: order) }
        .onChange(of: today.query) { _, _ in today.clearSelection() }
        .onChange(of: scope) { _, _ in
            today.clearSelection()
            today.keeping.removeAll()
        }
        .onChange(of: model.composerDraft) { _, _ in completionIndex = 0 }
        .onChange(of: paper.composerRequest, initial: true) { _, request in
            guard request != nil, !isDone else { return }
            today.clearSelection()
            endSearch()
        }
        .onAppear {
            today.keeping.removeAll()
            installKeys()
        }
        .onDisappear(perform: removeKeys)
    }

    // MARK: - Search

    private func searchField(matches: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(PiperTheme.faint)
            TextField("Search", text: $today.query)
                .textFieldStyle(.plain).focused($searching)
                .font(PiperTheme.paperUI(.row))
                .accessibilityLabel("Search Today")
                .onAppear { if showingSearch { DispatchQueue.main.async { searching = true } } }
            Text(matches == 1 ? "1 match" : "\(matches) matches")
                .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.faint).lineLimit(1).fixedSize()
            if !today.query.isEmpty {
                Button { today.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PiperTheme.faint) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: AppDefaults.Papers.composerHeight)
        .background(PiperTheme.paperTint, in: RoundedRectangle(cornerRadius: AppDefaults.Papers.rowRadius))
        .padding(.horizontal, AppDefaults.Papers.composerPadding.leading)
        .padding(.top, AppDefaults.Papers.composerPadding.top)
    }

    // MARK: - Composer

    /// The capture field on the first line of the paper. A note saves to the
    /// section of the list. A web link saves to read later. The address of a
    /// feed or a site opens the Sources paper to subscribe.
    private var composer: some View {
        let metrics = AppDefaults.Composer.self
        let papers = AppDefaults.Papers.self
        let inset = metrics.paperTextInset.height * 2
        let height = min(max(composerTextHeight, papers.composerHeight),
                         metrics.paperLineHeight * CGFloat(metrics.maxLines) + inset)
        let hint = composerHint
        return HStack(alignment: .top, spacing: 0) {
            Text("+")
                .font(PiperTheme.paperUI(.reading))
                .foregroundStyle(PiperTheme.paperFaint)
                .frame(width: papers.composerTextInset, height: papers.composerHeight)
                .accessibilityHidden(true)
            CaptureEditor(text: $model.composerDraft, focused: $composing,
                          placeholder: "Write a note, or paste a link to read later", paper: true,
                          contentHeight: { composerTextHeight = $0 })
                .frame(height: height)
            if let hint {
                Text(hint)
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                    .lineLimit(1).help(hint)
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

    private var composerHint: String? {
        guard composing else { return nil }
        if let action = composedAction { return "Return runs /\(action.skill.name) in \(action.folder.name)" }
        if !completions.isEmpty { return "Tab completes · ↑↓ choose" }
        switch CaptureDraft(model.composerDraft) {
        case .note: return nil
        case .link: return "Return saves it to read later"
        case .source: return "Return subscribes · ⌥Return reads later"
        }
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

    // MARK: - Lenses

    /// All, Notes, Reading, and Kept, as a segmented capsule. Keys 1 to 4 pick a lens.
    private func lenses(_ counts: [UnifiedStream.Lens: Int]) -> some View {
        let lenses = UnifiedStream.Lens.allCases
        return SegmentedCapsule(values: lenses, selection: paper.state.lens, title: \.title, count: { counts[$0] },
                                help: { "\($0.title) · \((lenses.firstIndex(of: $0) ?? 0) + 1)" }, pick: setLens)
            .padding(AppDefaults.Today.lensPadding)
    }

    private func setLens(_ lens: UnifiedStream.Lens) {
        paper.state.lens = lens
        today.clearSelection()
    }

    // MARK: - List

    private func list(_ groups: [UnifiedStream.Group], items: [StreamItem.Ref: StreamItem],
                      order: [StreamItem.Ref]) -> some View {
        let doneToday = isDone || paper.state.lens == .reading || !today.query.isEmpty ? []
            : UnifiedStream.doneToday(notes: store.notes, section: section)
                .filter { paper.state.lens == .all || !$0.isArticle }
                .map { StreamItem.capture($0, children: store.children(of: $0.id)) }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.title) { group in
                        Section {
                            ForEach(group.items) { item in
                                row(item, order: order).id(item.id)
                            }
                        } header: {
                            PaperGroupHeader(title: group.title,
                                             action: group.kind == .started && paper.state.lens == .all
                                                ? ("See All", { setLens(.reading) }) : nil)
                        }
                    }
                    if !doneToday.isEmpty {
                        PaperDoneToday(count: doneToday.count, shown: showsDoneToday) { showsDoneToday.toggle() }
                        if showsDoneToday {
                            ForEach(doneToday) { item in row(item, order: order).id(item.id) }
                        }
                    }
                }
                .padding(AppDefaults.Papers.listPadding)
                .padding(.bottom, today.multiple ? AppDefaults.Today.barHeight + AppDefaults.Today.barBottom : 0)
            }
            .overlay { if groups.isEmpty && doneToday.isEmpty { empty } }
            .onChange(of: today.anchor) { _, ref in
                if let ref { withAnimation(motion) { proxy.scrollTo(ref) } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var empty: some View {
        if !today.query.isEmpty {
            PaperEmpty(symbol: "magnifyingglass", title: "No Results", detail: "Try another word.")
        } else if isDone {
            PaperEmpty(symbol: "checkmark.circle", title: "Nothing Done", detail: "Items that you mark as done show here.")
        } else {
            switch paper.state.lens {
            case .reading: PaperEmpty(symbol: "book", title: "Nothing to Read", detail: "Paste a link above, or press Shift twice on a web page.")
            case .kept: PaperEmpty(symbol: "star", title: "Nothing Kept", detail: "Press K on a row to keep it.")
            case .notes, .all: PaperEmpty(symbol: "tray", title: "Nothing Today", detail: "Write a note above, or press Shift twice in another app.")
            }
        }
    }

    private func row(_ item: StreamItem, order: [StreamItem.Ref]) -> some View {
        TodayRow(item: item, selected: today.selection.contains(item.id), model: model,
                 verbs: verbs(for: item, order: order),
                 section: section == nil && item.note?.section != Note.inbox ? item.note?.section : nil) {
            click(item, order: order)
        }
    }

    // MARK: - Tray

    /// The clipboard texts at the foot of the paper, the newest first.
    private func trayView(_ tray: [StreamItem], items: [StreamItem.Ref: StreamItem], order: [StreamItem.Ref]) -> some View {
        let limit = showsWholeTray ? tray.count : min(tray.count, AppDefaults.Today.trayLimit)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Clipboard").font(PiperTheme.paperUI(.body, weight: .semibold)).foregroundStyle(PiperTheme.secondaryLabel)
                Text("\(tray.count)").font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint).monospacedDigit()
                Spacer()
                if tray.count > AppDefaults.Today.trayLimit {
                    Button(showsWholeTray ? "Show Less" : "Show All") { withAnimation(motion) { showsWholeTray.toggle() } }
                        .buttonStyle(.plain).foregroundStyle(PiperTheme.brand)
                }
                Menu {
                    Button("Clear Clipboard History") { withAnimation(motion) { model.clipboard.clear() } }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(PiperTheme.paperMuted)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Clipboard options")
            }
            .font(PiperTheme.paperUI(.body))
            .padding(.horizontal, AppDefaults.Papers.listRowPadding.leading)
            .padding(.top, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(tray.prefix(limit)) { item in row(item, order: order) }
                }
            }
            .frame(maxHeight: showsWholeTray ? AppDefaults.Papers.feedSize.height / 3 : nil)
            .fixedSize(horizontal: false, vertical: !showsWholeTray)
        }
        .padding(.horizontal, AppDefaults.Papers.listPadding.leading)
        .padding(.bottom, 6)
        .overlay(alignment: .top) { Rectangle().fill(PiperTheme.paperRule).frame(height: 1).padding(.horizontal, AppDefaults.Papers.footMargin) }
    }

    // MARK: - Floating Bar And Undo

    @ViewBuilder private func floating(items: [StreamItem.Ref: StreamItem], order: [StreamItem.Ref]) -> some View {
        VStack(spacing: 8) {
            if let undo = today.undo {
                UndoToast(offer: undo, run: today.runUndo)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if today.multiple, !today.selection.isEmpty {
                SelectionBar(count: today.selection.count, canMerge: selected(items, order).compactMap(\.note).count > 1,
                             model: model, verbs: verbs(for: selected(items, order), order: order),
                             cancel: today.clearSelection)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, AppDefaults.Today.barBottom)
        .animation(motion, value: today.undo?.id)
        .animation(motion, value: today.multiple)
    }

    // MARK: - Actions

    /// The selected rows in the order of the list.
    private func selected(_ items: [StreamItem.Ref: StreamItem], _ order: [StreamItem.Ref]) -> [StreamItem] {
        order.filter(today.selection.contains).compactMap { items[$0] }
    }

    /// The verbs of one row. A row that is part of a selection of several
    /// acts on the whole selection.
    private func verbs(for item: StreamItem, order: [StreamItem.Ref]) -> RowVerbs {
        RowVerbs(
            open: { open(item) },
            keep: { withAnimation(motion) { today.keep(targets(item)) } },
            done: { withAnimation(motion) { today.done(targets(item)) } },
            file: { today.filing = targets(item) },
            send: { today.send(targets(item), action: $0) },
            ask: { today.ask(item) },
            copy: { today.copy(targets(item)) },
            delete: { withAnimation(motion) { today.delete(targets(item)) } },
            edit: item.note.map { note in { editing = model.editCapture(note) } },
            editInWindow: item.note.map { note in { model.openNoteEditor?(note) } },
            merge: today.multiple && today.selection.contains(item.id) && today.selection.count > 1
                ? { today.merge(targets(item)) } : nil,
            openFeed: (item.articles.first?.feedID).map { feed in { paper.pick(.feed(feed)) } },
            stopSession: item.note.flatMap { agents.runner.latestSession(for: $0.id) }.flatMap { session in
                session.isActive ? { agents.runner.stop(session) } : nil
            })
    }

    /// The verbs of the selection bar.
    private func verbs(for items: [StreamItem], order: [StreamItem.Ref]) -> RowVerbs {
        RowVerbs(open: {}, keep: { withAnimation(motion) { today.keep(items) } },
                 done: { withAnimation(motion) { today.done(items) } },
                 file: { today.filing = items }, send: { today.send(items, action: $0) },
                 ask: { if let first = items.first { today.ask(first) } },
                 copy: { today.copy(items) }, delete: { withAnimation(motion) { today.delete(items) } },
                 merge: { today.merge(items) })
    }

    /// The rows that a verb of a row acts on: the selection, when the row is
    /// part of a selection of several, or else the row.
    private func targets(_ item: StreamItem) -> [StreamItem] {
        guard today.multiple, today.selection.contains(item.id), today.selection.count > 1 else { return [item] }
        let items = currentItems()
        return currentOrder().filter(today.selection.contains).compactMap { items[$0] }
    }

    /// The groups and the tray as the list shows them now.
    private func current() -> (groups: [UnifiedStream.Group], tray: [StreamItem]) {
        guard !isDone else { return (UnifiedStream.done(notes: store.notes, query: today.query), []) }
        let stream = UnifiedStream(today.input(), lens: paper.state.lens, section: section, query: today.query)
        return (stream.groups, stream.tray)
    }

    private func currentItems() -> [StreamItem.Ref: StreamItem] {
        let (groups, tray) = current()
        return Self.index(groups, tray)
    }

    private func currentOrder() -> [StreamItem.Ref] {
        let (groups, tray) = current()
        return Self.order(groups, tray)
    }

    private static func order(_ groups: [UnifiedStream.Group], _ tray: [StreamItem]) -> [StreamItem.Ref] {
        groups.flatMap(\.items).map(\.id) + tray.map(\.id)
    }

    private static func index(_ groups: [UnifiedStream.Group], _ tray: [StreamItem]) -> [StreamItem.Ref: StreamItem] {
        Dictionary((groups.flatMap(\.items) + tray).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// A click selects the row. Command-click and Shift-click select several
    /// rows. A click on the selected row opens it.
    private func click(_ item: StreamItem, order: [StreamItem.Ref]) {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        composing = false
        searching = false
        window()?.makeFirstResponder(nil)
        if !flags.intersection([.command, .shift]).isEmpty {
            today.extend(to: item.id, range: flags.contains(.shift), in: order)
            return
        }
        if today.selection == [item.id] {
            open(item)
        } else {
            today.select(item.id)
            if item.kind != .clip && item.kind != .digest { open(item) }
        }
    }

    /// Opens a row as a reader paper. A digest shows the list of its feed. A
    /// clipboard text goes back on the clipboard.
    private func open(_ item: StreamItem) {
        switch item.id {
        case .note(let id): desk?.open(.note(id))
        case .article(let id):
            today.keeping.insert(id)
            desk?.open(.article(id))
        case .digest(let feed, _): paper.pick(.feed(feed))
        case .clip:
            if let text = item.clip?.text, Clipboard.copy(text) { store.status = "Copied" }
        }
    }

    // MARK: - Composer Actions

    private func complete(_ action: FolderAgents.Action, run: Bool) {
        chosenAction = action
        if run && action.skill.argumentHint == nil {
            model.composerDraft = "/" + action.skill.name
            save(readLater: false)
        } else {
            model.composerDraft = "/" + action.skill.name + " "
        }
    }

    /// Saves the capture field. A command runs its skill. A link saves to
    /// read later. A feed or a site address subscribes, unless `readLater`.
    private func save(readLater: Bool) {
        guard canSave else { return }
        if let command = SlashCommand(model.composerDraft), let action = composedAction {
            if agents.run(command, action: action) != nil { clearComposer() }
            return
        }
        let target = section ?? (store.sections.contains(Note.inbox) ? Note.inbox : store.activeSection)
        switch CaptureDraft(model.composerDraft) {
        case .source(let url) where !readLater:
            paper.showSources(address: url.absoluteString)
            clearComposer()
        case .link(let url), .source(let url):
            if !store.keep(links: [KeptLink(url: url, source: "Piper")], to: target).isEmpty { clearComposer() }
        case .note:
            let heading = model.composerDraft.hasPrefix("# ") && !model.composerDraft.contains("\n")
            guard store.add(model.composerDraft, to: target) else { return }
            clearComposer()
            // "# Name" alone creates or chooses a section. The list then shows it.
            if heading { paper.pick(.today(section: store.activeSection)) }
        }
    }

    private func clearComposer() {
        model.composerDraft = ""
        chosenAction = nil
        today.query = ""
        showingSearch = false
        today.clearSelection()
        composing = true
    }

    private func beginSearch() {
        composing = false
        showingSearch = true
        searching = true
    }

    private func endSearch() {
        today.query = ""
        showingSearch = false
        searching = false
        composing = !isDone
    }

    // MARK: - Keys

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// The keys of Today while the feed paper shows the list and has the focus.
    private func installKeys() {
        removeKeys()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = PaperKey.focusedWindow, window.attachedSheet == nil,
                  window.windowController is FeedPaperController, !paper.showsIndex,
                  paper.state.scope.showsCaptures else { return event }
            return handle(event, in: window) ? nil : event
        }
    }

    private func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let textView = window.firstResponder as? NSTextView
        if textView?.hasMarkedText() == true { return false }
        let editingText = textView != nil
        let plain = flags.isDisjoint(with: [.shift, .command, .option, .control])
        if editingText, plain, !completions.isEmpty {
            let current = min(completionIndex, completions.count - 1)
            switch event.keyCode {
            case 125: completionIndex = min(current + 1, completions.count - 1); return true
            case 126: completionIndex = max(current - 1, 0); return true
            case 48: complete(completions[current], run: false); return true
            case 36: complete(completions[current], run: true); return true
            case 53: model.composerDraft = ""; return true
            default: break
            }
        }
        if event.keyCode == 36, composing, !flags.contains(.shift), !flags.contains(.control), !flags.contains(.command) {
            save(readLater: flags.contains(.option))
            return true
        }
        let order = currentOrder()
        let items = currentItems()
        let chosen = order.filter(today.selection.contains).compactMap { items[$0] }
        if event.keyCode == 53 {
            if !today.selection.isEmpty { today.clearSelection(); composing = !isDone }
            else if searchMode { endSearch() }
            else { return false }
            return true
        }
        if flags.contains(.command), !flags.contains(.option), !flags.contains(.control) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f": beginSearch()
            case "a" where !editingText:
                today.selection = Set(order)
                today.multiple = !order.isEmpty
            case "c" where !editingText && !chosen.isEmpty: today.copy(chosen, asList: flags.contains(.shift))
            case "z" where !editingText:
                if today.undo != nil { today.runUndo() } else { store.undo() }
            default:
                if event.keyCode == 36, flags.contains(.shift), !editingText, !chosen.isEmpty {
                    today.send(chosen, action: nil)
                    return true
                }
                if event.keyCode == 36, !editingText, let note = chosen.first?.note {
                    model.openNoteEditor?(note)
                    return true
                }
                return false
            }
            return true
        }
        guard !editingText, !flags.contains(.option), !flags.contains(.control) else { return false }
        switch event.keyCode {
        case 125, 126:
            today.move(event.keyCode == 125 ? 1 : -1, extending: flags.contains(.shift), in: order)
            return true
        case 36, 76:
            guard let first = chosen.first else { return false }
            open(first)
            return true
        case 51, 117:
            guard !chosen.isEmpty else { return false }
            withAnimation(motion) { today.delete(chosen) }
            return true
        case 49:
            guard !chosen.isEmpty else { return false }
            withAnimation(motion) { today.done(chosen) }
            return true
        default:
            break
        }
        guard !flags.contains(.shift), let key = event.charactersIgnoringModifiers?.lowercased().first else { return false }
        switch key {
        case "1"..."4" where !isDone:
            setLens(UnifiedStream.Lens.allCases[Int(String(key))! - 1])
        case "k" where !chosen.isEmpty: withAnimation(motion) { today.keep(chosen) }
        case "e" where !chosen.isEmpty: withAnimation(motion) { today.done(chosen) }
        case "f" where !chosen.isEmpty: today.filing = chosen
        case "s" where !chosen.isEmpty: today.send(chosen, action: nil)
        case "m" where chosen.count > 1: today.merge(chosen)
        default: return false
        }
        return true
    }
}

// MARK: - Floating Parts

/// The Undo button after Done or Delete. It leaves after a few seconds.
struct UndoToast: View {
    let offer: UndoOffer
    let run: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(offer.message).foregroundStyle(PiperTheme.paperInk)
            Button("Undo", action: run)
                .buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(PiperTheme.brand)
                .help("Undo · ⌘Z")
        }
        .font(PiperTheme.paperUI(.body))
        .padding(.horizontal, 16)
        .frame(height: AppDefaults.Today.barHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(PiperTheme.paperRule, lineWidth: 1))
        .shadow(color: PiperTheme.lensShadow, radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }
}

/// The floating bar of a selection of several rows: Keep, Done, File, Send,
/// Merge, and Copy.
struct SelectionBar: View {
    let count: Int
    let canMerge: Bool
    let model: AppModel
    let verbs: RowVerbs
    let cancel: () -> Void

    var body: some View {
        // The keys show beside the labels when the paper is wide enough.
        ViewThatFits(in: .horizontal) {
            items(keys: true)
            items(keys: false)
        }
        .font(PiperTheme.paperUI(.body, weight: .medium))
        .padding(.horizontal, 8)
        .frame(height: AppDefaults.Today.barHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(PiperTheme.paperRule, lineWidth: 1))
        .shadow(color: PiperTheme.lensShadow, radius: 8, y: 2)
    }

    private func items(keys: Bool) -> some View {
        HStack(spacing: AppDefaults.Today.barSpacing) {
            Text("\(count) selected").foregroundStyle(PiperTheme.paperMuted).padding(.horizontal, 8).fixedSize()
            bar("Keep", key: "K", keys: keys, action: verbs.keep)
            bar("Done", key: "E", keys: keys, action: verbs.done)
            bar("File", key: "F", keys: keys, action: verbs.file)
            Menu { SendItems(model: model, verbs: verbs) } label: { label("Send", key: "S", keys: keys) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Send · S")
                .accessibilityLabel("Send")
            bar("Merge", key: "M", keys: keys, action: verbs.merge ?? {}).disabled(!canMerge)
            bar("Copy", key: "⌘C", keys: keys, action: verbs.copy)
            Button(action: cancel) { Image(systemName: "xmark").foregroundStyle(PiperTheme.paperMuted).frame(width: 24, height: 24) }
                .buttonStyle(.plain).help("Clear the selection · Escape").accessibilityLabel("Clear the selection")
        }
    }

    private func bar(_ title: String, key: String, keys: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { label(title, key: key, keys: keys) }
            .buttonStyle(.plain)
            .help("\(title) · \(key)")
            .accessibilityLabel(title)
    }

    private func label(_ title: String, key: String, keys: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(PiperTheme.paperInk)
            if keys { Text(key).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint) }
        }
        .fixedSize()
        .padding(.horizontal, keys ? 8 : 6)
        .frame(height: AppDefaults.Today.verbButton)
        .contentShape(Capsule())
    }
}
