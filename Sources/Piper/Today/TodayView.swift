import AppKit
import Agents
import Captures
import Feeds
import PiperCore
import Stream
import SwiftUI

/// What the capture field holds: a note, a web link to read later, the
/// address of a feed or a site, which the Sources paper subscribes to, or
/// `# Name` alone on one line, which creates or chooses a section.
enum CaptureDraft: Equatable {
    case note
    case link(URL)
    case source(URL)
    /// The name after `# `. It is empty when the line has no name.
    case section(String)

    init(_ text: String) {
        if text.hasPrefix("# "), !text.contains("\n") {
            self = .section(String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            return
        }
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
        return Array(agents.completions(for: partial).prefix(FolderAgents.completionLimit))
    }

    /// The folder and skill that Return runs, when the composer holds a command.
    private var composedAction: FolderAgents.Action? {
        guard let command = SlashCommand(model.composerDraft) else { return nil }
        if let chosenAction, chosenAction.skill.name == command.name { return chosenAction }
        return agents.action(for: command)
    }

    /// The list that shows. The model builds it again only when an input changes.
    private var shown: TodayList { today.list(lens: paper.state.lens, scope: scope) }

    var body: some View {
        let shown = shown
        VStack(spacing: 0) {
            if searchMode { searchField(matches: shown.groups.flatMap(\.items).count) }
            if !isDone { composer }
            if let stream = shown.stream { lenses(stream.counts.lenses) }
            list(shown)
                .overlay(alignment: .bottom) { skillList }
                .overlay(alignment: .bottom) { floating(shown) }
            if !shown.tray.isEmpty { trayView(shown) }
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
        .onChange(of: shown.order) { _, order in today.keepSelection(in: order) }
        .onChange(of: today.query) { _, _ in today.clearSelection() }
        .onChange(of: scope) { _, scope in
            today.clearSelection()
            today.resetKeeping()
            if scope.showsCaptures { paper.listKeys = keys }
        }
        .onChange(of: model.composerDraft) { _, _ in completionIndex = 0 }
        .onChange(of: paper.composerRequest, initial: true) { _, request in
            guard request != nil, !isDone else { return }
            today.clearSelection()
            endSearch()
        }
        .onAppear {
            today.resetKeeping()
            paper.listKeys = keys
        }
    }

    // MARK: - Search

    private func searchField(matches: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(PiperTheme.paperFaint)
            TextField("Search", text: $today.query)
                .textFieldStyle(.plain).focused($searching)
                .font(PiperTheme.paperUI(.row))
                .accessibilityLabel("Search Today")
                .onExitCommand { _ = escape() }
                .onAppear { if showingSearch { DispatchQueue.main.async { searching = true } } }
            Text(matches == 1 ? "1 match" : "\(matches) matches")
                .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint).lineLimit(1).fixedSize()
            if !today.query.isEmpty {
                Button { today.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PiperTheme.paperFaint) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Metrics.composerHeight)
        .background(PiperTheme.paperTint, in: RoundedRectangle(cornerRadius: PaperRowMetrics.rowRadius))
        .padding(.horizontal, Metrics.composerPadding.leading)
        .padding(.top, Metrics.composerPadding.top)
    }

    // MARK: - Composer

    /// The capture field on the first line of the paper. A note saves to the
    /// section of the list. A web link saves to read later. The address of a
    /// feed or a site opens the Sources paper to subscribe.
    private var composer: some View {
        let metrics = CaptureEditor.Metrics.self
        let field = Metrics.self
        let inset = metrics.textInset.height * 2
        let height = min(max(composerTextHeight, field.composerHeight),
                         metrics.lineHeight * CGFloat(field.maxLines) + inset)
        let hint = composerHint
        return HStack(alignment: .top, spacing: 0) {
            Text("+")
                .font(PiperTheme.paperUI(.reading))
                .foregroundStyle(PiperTheme.paperFaint)
                .frame(width: field.composerTextInset, height: field.composerHeight)
                .accessibilityHidden(true)
            CaptureEditor(text: $model.composerDraft, focused: $composing,
                          placeholder: "Write a note, or paste a link to read later",
                          command: composerCommand, contentHeight: { composerTextHeight = $0 })
                .frame(height: height)
            if let hint {
                Text(hint)
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                    .lineLimit(1).help(hint)
                    .padding(.trailing, 14)
                    .frame(height: field.composerHeight)
                    .allowsHitTesting(false)
            }
        }
        .background(PiperTheme.paperTint, in: RoundedRectangle(cornerRadius: PaperRowMetrics.rowRadius, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: PaperRowMetrics.rowRadius + field.focusRingWidth, style: .continuous)
                .fill(composing ? PiperTheme.brand : .clear)
                .padding(-field.focusRingWidth)
        }
        .padding(field.composerPadding)
    }

    private var composerHint: String? {
        guard composing else { return nil }
        if let action = composedAction { return "Return runs /\(action.skill.name) in \(action.folder.name)" }
        if !completions.isEmpty { return "Tab completes · ↑↓ choose" }
        switch CaptureDraft(model.composerDraft) {
        case .note, .section: return nil
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
            .padding(.horizontal, Metrics.completionMargin)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Lenses

    /// All, Notes, Reading, and Kept, as a segmented capsule. Keys 1 to 4 pick a lens.
    private func lenses(_ counts: [UnifiedStream.Lens: Int]) -> some View {
        let lenses = UnifiedStream.Lens.allCases
        return SegmentedCapsule(values: lenses, selection: paper.state.lens, title: \.title, count: { counts[$0] },
                                help: { "\($0.title) · \((lenses.firstIndex(of: $0) ?? 0) + 1)" }, pick: setLens)
            .padding(Metrics.lensPadding)
    }

    private func setLens(_ lens: UnifiedStream.Lens) {
        paper.state.lens = lens
        today.clearSelection()
    }

    // MARK: - List

    private func list(_ shown: TodayList) -> some View {
        let groups = shown.groups
        let order = shown.order
        let doneToday = shown.doneToday
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
                .padding(PaperRowMetrics.listPadding)
                .padding(.bottom, today.multiple ? Metrics.barHeight + Metrics.barBottom : 0)
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
                 verbs: verbs(for: item),
                 section: section == nil && item.note?.section != Note.inbox ? item.note?.section : nil) {
            click(item, order: order)
        }
    }

    // MARK: - Tray

    /// The clipboard texts at the foot of the paper, the newest first.
    private func trayView(_ shown: TodayList) -> some View {
        let tray = shown.tray
        let order = shown.order
        let limit = showsWholeTray ? tray.count : min(tray.count, Metrics.trayLimit)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Clipboard").font(PiperTheme.paperUI(.body, weight: .semibold)).foregroundStyle(PiperTheme.paperMuted)
                Text("\(tray.count)").font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint).monospacedDigit()
                Spacer()
                if tray.count > Metrics.trayLimit {
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
            .padding(.horizontal, PaperRowMetrics.listRowPadding.leading)
            .padding(.top, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(tray.prefix(limit)) { item in row(item, order: order) }
                }
            }
            .frame(maxHeight: showsWholeTray ? FeedPaperController.Metrics.feedSize.height / 3 : nil)
            .fixedSize(horizontal: false, vertical: !showsWholeTray)
        }
        .padding(.horizontal, PaperRowMetrics.listPadding.leading)
        .padding(.bottom, 6)
        .overlay(alignment: .top) { Rectangle().fill(PiperTheme.paperRule).frame(height: 1).padding(.horizontal, HintStrip.Metrics.footMargin) }
    }

    // MARK: - Floating Bar And Undo

    @ViewBuilder private func floating(_ shown: TodayList) -> some View {
        VStack(spacing: 8) {
            if let undo = today.undo {
                UndoToast(offer: undo, run: today.runUndo)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if today.multiple, !today.selection.isEmpty {
                let selected = shown.rows(today.selection)
                SelectionBar(count: today.selection.count, canMerge: selected.compactMap(\.note).count > 1,
                             model: model, verbs: verbs(for: selected),
                             cancel: today.clearSelection)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, Metrics.barBottom)
        .animation(motion, value: today.undo?.id)
        .animation(motion, value: today.multiple)
    }

    // MARK: - Actions

    /// The verbs of one row. A row that is part of a selection of several
    /// acts on the whole selection.
    private func verbs(for item: StreamItem) -> RowVerbs {
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
    private func verbs(for items: [StreamItem]) -> RowVerbs {
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
        return chosen()
    }

    /// The selected rows, in the order of the list.
    private func chosen() -> [StreamItem] {
        shown.rows(today.selection)
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
            today.open(article: id)
            if let article = item.articles.first { model.articleActions.openAsPaper(article, on: desk) }
        case .digest(let feed, _): paper.pick(.feed(feed))
        case .clip:
            if let text = item.clip?.text, Clipboard.copy(text) { model.messages.show("Copied") }
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
            do {
                guard let session = try agents.run(command, action: action) else { return }
                model.messages.show("Running /\(command.name) in \(session.folderName)")
                clearComposer()
            } catch {
                model.messages.report(error)
            }
            return
        }
        let target = section ?? (store.sections.contains(Note.inbox) ? Note.inbox : store.activeSection)
        switch CaptureDraft(model.composerDraft) {
        case .source(let url) where !readLater:
            paper.showSources(address: url.absoluteString)
            clearComposer()
        case .link(let url), .source(let url):
            do { try store.keep(links: [KeptLink(url: url, source: "Piper")], to: target) } catch { return model.messages.report(error) }
            clearComposer()
        case .section(let name):
            guard !name.isEmpty else { return }
            do { try store.chooseSection(name) } catch { return model.messages.report(error) }
            clearComposer()
            paper.pick(.today(section: store.activeSection))
        case .note:
            do { try store.add(model.composerDraft, section: target) } catch { return model.messages.report(error) }
            clearComposer()
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

    /// The keys of Today, which the feed paper runs while Today shows and no
    /// text has the focus. The verb keys act on the selected rows.
    private var keys: [PaperKey] {
        let today = today
        let selected = { !today.selection.isEmpty }
        let lenses = UnifiedStream.Lens.allCases.enumerated().map { offset, lens in
            PaperKey(key: CommandKey(String(offset + 1), []), title: "lens", isOn: { !isDone }) { setLens(lens) }
        }
        let keys = [
            PaperKey(key: .up, title: "move") { today.move(-1, extending: false, in: shown.order) },
            PaperKey(key: .down, title: "move") { today.move(1, extending: false, in: shown.order) },
            PaperKey(key: CommandKey.up.shifted, title: "add to the selection") { today.move(-1, extending: true, in: shown.order) },
            PaperKey(key: CommandKey.down.shifted, title: "add to the selection") { today.move(1, extending: true, in: shown.order) },
            PaperKey(key: .enter, title: "open as a paper", isOn: selected) { if let first = chosen().first { open(first) } },
            PaperKey(key: CommandKey("k", []), title: "keep", isOn: selected) { withAnimation(motion) { today.keep(chosen()) } },
            PaperKey(key: CommandKey("e", []), title: "done", isOn: selected) { withAnimation(motion) { today.done(chosen()) } },
            PaperKey(key: .space, title: "done", isOn: selected) { withAnimation(motion) { today.done(chosen()) } },
            PaperKey(key: CommandKey("f", []), title: "file", isOn: selected) { today.filing = chosen() },
            PaperKey(key: CommandKey("s", []), title: "send", isOn: selected) { today.send(chosen(), action: nil) },
            PaperKey(key: CommandKey("m", []), title: "merge", isOn: { today.selection.count > 1 }) { today.merge(chosen()) },
            PaperKey(key: .delete, title: "delete", isOn: { today.selection.contains(where: TodayModel.canDelete) }) {
                withAnimation(motion) { today.delete(chosen()) }
            }
        ] + lenses + [
            PaperKey(key: .escape, title: "clear the selection", isOn: selected) { clearSelection() },
            PaperKey(key: .escape, title: "end the search", isOn: { searchMode }) { endSearch() },
            PaperKey(key: CommandKey("f"), title: "search", inText: true) { beginSearch() },
            PaperKey(key: CommandKey("a"), title: "select all") {
                let order = shown.order
                today.selection = Set(order)
                today.multiple = !order.isEmpty
            },
            PaperKey(key: CommandKey("c"), title: "copy", isOn: selected) { today.copy(chosen()) },
            PaperKey(key: CommandKey("c", [.shift, .command]), title: "copy as a list", isOn: selected) { today.copy(chosen(), asList: true) },
            PaperKey(key: CommandKey("\r"), title: "edit", isOn: selected) {
                if let note = chosen().first?.note { model.openNoteEditor?(note) }
            },
            PaperKey(key: CommandKey("\r", [.shift, .command]), title: "send", isOn: selected) { today.send(chosen(), action: nil) }
        ]
        let paper = paper
        return keys.map { $0.only(when: { paper.state.scope.showsCaptures }) }
    }

    private func clearSelection() {
        today.clearSelection()
        composing = !isDone
    }

    /// Escape in the capture field or in the search field clears the
    /// selection, and then ends the search.
    ///
    /// - Returns: True when Escape did one of these.
    private func escape() -> Bool {
        if !today.selection.isEmpty { clearSelection() }
        else if searchMode { endSearch() }
        else { return false }
        return true
    }

    /// The keys of the capture field. While the skill list shows, the arrows
    /// move its highlight, Tab puts the skill in the field, Return does the
    /// same or runs the skill, and Escape clears the field. Return saves the
    /// field, and Option-Return saves an address to read later.
    private func composerCommand(_ selector: Selector) -> Bool {
        let flags = (NSApp.currentEvent?.modifierFlags ?? []).intersection([.shift, .control, .option, .command])
        if flags.isEmpty, !completions.isEmpty {
            let current = min(completionIndex, completions.count - 1)
            switch selector {
            case #selector(NSResponder.moveDown(_:)): completionIndex = min(current + 1, completions.count - 1)
            case #selector(NSResponder.moveUp(_:)): completionIndex = max(current - 1, 0)
            case #selector(NSResponder.insertTab(_:)): complete(completions[current], run: false)
            case #selector(NSResponder.insertNewline(_:)): complete(completions[current], run: true)
            case #selector(NSResponder.cancelOperation(_:)): model.composerDraft = ""
            default: return false
            }
            return true
        }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            guard flags.isDisjoint(with: [.shift, .control, .command]) else { return false }
            save(readLater: flags.contains(.option))
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            return escape()
        default:
            return false
        }
    }
}

// MARK: - Floating Parts

extension TodayView {
    enum Metrics {
        /// The capture field on the first line of the feed paper.
        static let composerHeight: CGFloat = 48
        static let composerPadding = EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20)
        static let composerTextInset: CGFloat = 40
        static let focusRingWidth: CGFloat = 3
        /// The most lines that the capture field shows before it scrolls.
        static let maxLines = 5
        /// The space between the edge of the list and the skill list.
        static let completionMargin: CGFloat = 14
        static let lensPadding = EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20)
        /// The clipboard texts that the tray at the foot shows at most.
        static let trayLimit = 3
        /// The floating bar of a selection of several rows.
        static let barHeight: CGFloat = 44
        static let barBottom: CGFloat = 16
        static let barSpacing: CGFloat = 4
    }
}

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
        .frame(height: TodayView.Metrics.barHeight)
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
        .frame(height: TodayView.Metrics.barHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(PiperTheme.paperRule, lineWidth: 1))
        .shadow(color: PiperTheme.lensShadow, radius: 8, y: 2)
    }

    private func items(keys: Bool) -> some View {
        HStack(spacing: TodayView.Metrics.barSpacing) {
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
        .frame(height: TodayRow.Metrics.verbButton)
        .contentShape(Capsule())
    }
}
