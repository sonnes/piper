import AppKit
import SwiftUI

private enum PanelSheet: Identifiable {
    case sections(moving: Bool), edit(CaptureEditSession), export
    var id: String {
        switch self {
        case .sections: return "sections"
        case .edit: return "edit"
        case .export: return "export"
        }
    }
}

struct PanelView: View {
    @Bindable var store: AppStore
    let model: AppModel

    init(model: AppModel) {
        self.model = model
        self.store = model.store
    }

    @AppStorage("composerDraft") private var draft = ""
    @State private var sheet: PanelSheet?
    @State private var keyMonitor: Any?
    @State private var selectionAnchor: UUID?
    @FocusState private var searching: Bool
    @State private var composing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Search shows every section. Otherwise the active section tab filters the list.
    private var searchMode: Bool { searching || !store.query.isEmpty }
    private var displayedSections: [String] {
        searchMode ? store.sections.filter { !store.visibleNotes(in: $0).isEmpty } : [store.activeSection]
    }
    private var matchingNotes: [Note] { displayedSections.flatMap { store.visibleNotes(in: $0) } }
    private var clipboardEntries: [ClipboardEntry] {
        model.clipboard.entries.filter {
            store.query.isEmpty || ($0.text + " Clipboard " + store.activeSection).localizedCaseInsensitiveContains(store.query)
        }
    }
    private var canSave: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.12) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rule()
            if !model.accessibilityEnabled { capturePermission }
            noteList
            if !store.selection.isEmpty { selectionBar }
            composer
            footer
        }
        .id(model.style)
        .background(PiperTheme.page)
        .foregroundStyle(PiperTheme.ink)
        .tint(PiperTheme.accent)
        .accentColor(PiperTheme.accent)
        .sheet(item: $sheet) { item in
            switch item {
            case .sections(let moving):
                SectionPicker(sections: store.sections, current: store.activeSection, moving: moving) { section in
                    if moving { store.move(to: section) }
                    else if !store.chooseSection(section) { return }
                    store.status = "Capturing to \(store.activeSection)"
                    sheet = nil
                }
            case .edit(let session):
                NoteEditor(model: model, session: session) {
                    if model.saveCaptureEdit(session) { sheet = nil }
                }
            case .export: ExportView(model: model)
            }
        }
        .alert("Piper", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: store.query) { _, _ in
            store.selection.removeAll()
            selectionAnchor = nil
        }
        .onChange(of: store.activeSection) { _, _ in
            store.selection.removeAll()
            selectionAnchor = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? CapturePanel, window.attachedSheet == nil else { return }
            if store.selection.isEmpty && store.query.isEmpty { composing = true }
        }
        .onAppear {
            composing = true
            installKeyboardShortcuts()
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            if searchMode { searchBar } else { sectionTabs }
            IconButton(title: "Search · ⌘F", icon: "magnifyingglass", active: searchMode) {
                if searchMode { store.query = ""; searching = false; composing = true } else { searching = true }
            }
            Menu {
                Button("Capture Clipboard", systemImage: "doc.on.clipboard") { store.captureClipboard() }
                Button("Choose Section…", systemImage: "tray") { sheet = .sections(moving: false) }
                Button("Browse Wiki", systemImage: "books.vertical") { model.route = "wiki"; model.openLibrary?() }
                Divider()
                Button("Settings…", systemImage: "gearshape") { model.route = "settings"; model.openLibrary?() }
                Divider()
                Button("Undo Last Change", systemImage: "arrow.uturn.backward") { store.undo() }.disabled(!store.canUndo)
                Button("Close Capture") { (NSApp.keyWindow as? CapturePanel)?.orderOut(nil) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).foregroundStyle(PiperTheme.secondary)
                    .frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("More Actions").accessibilityLabel("More Actions")
        }
        .padding(.leading, 12).padding(.trailing, 8)
        .frame(height: 44)
    }

    private var sectionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(store.sections, id: \.self) { section in
                    let active = section == store.activeSection
                    Button { store.activeSection = section } label: {
                        HStack(spacing: 5) {
                            Text(section).lineLimit(1)
                            let open = store.notes.filter { $0.section == section && !$0.isDone }.count
                            if open > 0 { Text("\(open)").foregroundStyle(PiperTheme.faint).monospacedDigit() }
                        }
                        .font(PiperTheme.ui(12, weight: .medium))
                        .foregroundStyle(active ? PiperTheme.ink : PiperTheme.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 44)
                        .overlay(alignment: .bottom) {
                            if active && !PiperTheme.isPage {
                                Rectangle().fill(PiperTheme.accent).frame(height: 2).padding(.horizontal, 8)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(section) section")
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
                Button { sheet = .sections(moving: false) } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(PiperTheme.secondary)
                        .frame(width: 26, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("New Section · ⌘K").accessibilityLabel("New Section")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(PiperTheme.secondary)
            TextField("Search notes", text: $store.query)
                .textFieldStyle(.plain).focused($searching)
                .font(Font(PiperTheme.manuscript(size: 13)))
                .accessibilityLabel("Search notes and sections")
            Text(matchingNotes.count == 1 ? "1 match · Esc" : "\(matchingNotes.count) matches · Esc")
                .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary).lineLimit(1)
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var capturePermission: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Capture text from other apps").font(PiperTheme.ui(12, weight: .semibold))
            Text("Enable Accessibility to save a selection with \(model.captureShortcut).")
                .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
            Button("Enable Selection Capture") { model.requestAccessibility() }
                .buttonStyle(PiperButtonStyle()).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.radius + 1).strokeBorder(PiperTheme.rule, lineWidth: 1))
        .padding(.horizontal, 18).padding(.top, 12)
    }

    // MARK: List

    private var noteList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !clipboardEntries.isEmpty {
                        listLabel("Clipboard")
                        ForEach(clipboardEntries) { entry in
                            ClipboardRow(entry: entry, section: store.activeSection) {
                                withAnimation(motion) {
                                    if model.clipboard.save(entry.id) {
                                        store.selection.removeAll()
                                        selectionAnchor = nil
                                    }
                                }
                            }.id(entry.id).transition(.opacity)
                        }
                    }
                    ForEach(displayedSections, id: \.self) { section in
                        if searchMode || !clipboardEntries.isEmpty { listLabel(section) }
                        ForEach(store.visibleNotes(in: section)) { note in
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
                                canMerge: store.selection.contains(note.id) && store.selection.count > 1)
                            .id(note.id)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .overlay {
                if matchingNotes.isEmpty && clipboardEntries.isEmpty { emptyState }
            }
            .onChange(of: store.notes.count) { oldCount, newCount in
                if newCount > oldCount, let note = store.notes.last {
                    withAnimation(motion) { proxy.scrollTo(note.id, anchor: .bottom) }
                }
            }
            .onChange(of: selectionAnchor) { _, id in
                if let id { withAnimation(motion) { proxy.scrollTo(id) } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func listLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(PiperTheme.ui(10.5, weight: .semibold)).tracking(0.4)
            .foregroundStyle(PiperTheme.secondary)
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if store.query.isEmpty {
                Text(store.notes.isEmpty ? "Keep the useful parts" : "Nothing in \(store.activeSection)")
                    .font(PiperTheme.ui(14, weight: .medium))
                Text("Select text in another app, then press")
                    .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                Text(model.captureShortcut == "Shift, Shift" ? "⇧ ⇧" : "⌃ ⌥ C")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: PiperTheme.radius + 1).strokeBorder(PiperTheme.rule, lineWidth: 1))
                    .padding(.vertical, 4)
                    .accessibilityLabel(model.captureShortcut)
                Text("Or add a note below.")
                    .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
            } else {
                Text("No matching notes").font(PiperTheme.ui(14, weight: .medium))
                Text("Try another word or section name.")
                    .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .allowsHitTesting(false)
    }

    // MARK: Selection, composer, footer

    private var selectionBar: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 6) {
                Text("\(store.selection.count) selected").font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                Spacer(minLength: 0)
                Button("Merge") { store.merge() }.buttonStyle(PiperButtonStyle(ghost: true))
                    .disabled(store.selection.count < 2).help("Merge Notes · ⇧⌘M")
                Button("Move") { sheet = .sections(moving: true) }.buttonStyle(PiperButtonStyle(ghost: true))
                Button("Wiki") { model.prepareExport(); sheet = .export }.buttonStyle(PiperButtonStyle(ghost: true))
                    .help("Send to Wiki")
                Button("Copy as List") { store.copy(asList: true) }.buttonStyle(PiperButtonStyle(prominent: true))
                    .help("Copy as List · ⇧⌘C")
                Menu {
                    Button("Copy", action: { store.copy(asList: false) })
                    Button("Mark as Done / Reopen") { store.completeSelection() }
                    Button("Clear Selection") { store.selection.removeAll() }
                    Divider()
                    Button("Delete Notes", role: .destructive) { store.deleteSelection() }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).foregroundStyle(PiperTheme.secondary)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Selected note actions")
            }
            .padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 6)
            .background(PiperTheme.surface)
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rule()
            CaptureEditor(text: $draft, focused: $composing)
                .frame(height: 96)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 6) {
                if store.status == "Local notes" {
                    Text("Return saves to \(store.activeSection) · ⌘K change").lineLimit(1)
                } else {
                    Text(store.status).lineLimit(1).help(store.status)
                }
                Spacer(minLength: 4)
                if store.canUndo {
                    Button("Undo") { store.undo() }.buttonStyle(.plain).help("Undo Last Change")
                } else {
                    Text(model.captureShortcut == "Shift, Shift" ? "⇧⇧ capture" : "⌃⌥C capture")
                        .accessibilityLabel("\(model.captureShortcut) captures selected text")
                }
            }
            .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
            .padding(.horizontal, 18).frame(height: 30)
            .background(PiperTheme.surface)
        }
    }

    // MARK: Behavior

    private func selectNote(_ id: UUID) {
        composing = false
        searching = false
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
        let createsSection = draft.hasPrefix("# ") && !draft.contains("\n")
        if store.add(draft) {
            if createsSection { store.status = "Capturing to \(store.activeSection)" }
            draft = ""
            store.query = ""
            store.selection.removeAll()
            composing = true
        }
    }

    private func installKeyboardShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = NSApp.keyWindow as? CapturePanel, window.attachedSheet == nil else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let textView = window.firstResponder as? NSTextView
            if textView?.hasMarkedText() == true { return event }
            let editingText = textView != nil
            if event.keyCode == 53 {
                if !store.selection.isEmpty { store.selection.removeAll(); composing = true }
                else if !store.query.isEmpty || searching { store.query = ""; searching = false; composing = true }
                else { window.orderOut(nil) }
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
            case "f": searching = true
            case "n": store.selection.removeAll(); composing = true
            case "a" where !editingText: store.selection = Set(matchingNotes.map(\.id))
            case "c" where !editingText && !store.selection.isEmpty: store.copy(asList: flags.contains(.shift))
            case "m" where flags.contains(.shift) && !editingText: store.merge()
            case "z" where !editingText: store.undo()
            case "w": window.orderOut(nil)
            default: return event
            }
            return nil
        }
    }
}

// MARK: Rows

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let section: String
    let save: () -> Void
    @State private var hovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: save) {
            HStack(alignment: .top, spacing: 10) {
                Text(entry.text)
                    .font(Font(PiperTheme.manuscript(size: 14))).lineSpacing(5).lineLimit(4)
                    .foregroundStyle(hovered || contrast == .increased ? PiperTheme.ink : PiperTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if PiperTheme.isPage {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hovered ? PiperTheme.accent : PiperTheme.faint).padding(.top, 4)
                } else {
                    Text("unsaved").font(PiperTheme.ui(10)).foregroundStyle(PiperTheme.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(PiperTheme.rule, lineWidth: 1))
                }
            }
            .padding(.leading, PiperTheme.isPage ? 44 : 42).padding(.trailing, 18).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? PiperTheme.hover : .clear)
            .overlay(alignment: .leading) {
                if !PiperTheme.isPage {
                    DashedLine().stroke(hovered ? PiperTheme.accent : PiperTheme.faint, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                        .frame(width: 2)
                }
            }
            .overlay(alignment: .bottom) { Rule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Save to \(section)")
        .accessibilityLabel("Save clipboard item: \(String(entry.text.prefix(240)))")
        .accessibilityHint("Saves this item to \(section). Clipboard previews are unsaved.")
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private struct NoteRow: View {
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
    let canMerge: Bool

    private var formattedText: AttributedString {
        (try? AttributedString(markdown: note.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(note.text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: complete) {
                Circle()
                    .strokeBorder(note.isDone ? .clear : PiperTheme.faint, lineWidth: 1.5)
                    .background(Circle().fill(note.isDone ? PiperTheme.faint : .clear))
                    .frame(width: 14, height: 14)
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(note.isDone ? "Reopen note" : "Mark note as done")
            Button(action: select) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedText)
                        .font(Font(PiperTheme.manuscript(size: 14))).lineSpacing(5).lineLimit(4)
                        .strikethrough(note.isDone)
                        .foregroundStyle(note.isDone ? PiperTheme.secondary : PiperTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let source = note.sources.first {
                        Text(source).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary).lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("Command-click adds to the selection. Return edits the note.")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(selected ? PiperTheme.selection : PiperTheme.page)
        .overlay(alignment: .bottom) { Rule() }
        .overlay(alignment: .leading) { if selected && PiperTheme.isPage { Rectangle().fill(PiperTheme.accent).frame(width: 2) } }
        .contextMenu {
            Button("Copy") { copy(false) }
            Button("Copy as List") { copy(true) }
            Divider()
            Button(note.isDone ? "Reopen" : "Mark as Done", action: complete)
            Button("Edit", action: edit)
            Button("Edit in New Window", action: newWindow)
            Divider()
            Button("Merge Notes", action: merge).disabled(!canMerge)
            Button("Move to…") { prepareActions(); move() }
            if let source = note.sourceURLs.first, let url = URL(string: source), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                Divider()
                Button("Open Source") { NSWorkspace.shared.open(url) }
            }
        }
    }
}

// MARK: Sheets

/// A text field with a hairline border in Vault and an underline in Page.
struct PiperField: View {
    let title: String
    @Binding var text: String
    var hint: String?
    var lines: ClosedRange<Int>?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if let lines { TextField(title, text: $text, axis: .vertical).lineLimit(lines) }
                else { TextField(title, text: $text) }
            }
            .textFieldStyle(.plain).focused($focused)
            .font(PiperTheme.ui(13))
            if let hint {
                Text(hint).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary).padding(.top, 1)
            }
        }
        .padding(.horizontal, PiperTheme.isPage ? 0 : 10).padding(.vertical, 7)
        .overlay {
            if PiperTheme.isPage {
                VStack { Spacer(); Rectangle().fill(focused ? PiperTheme.accent : PiperTheme.rule).frame(height: 1) }
            } else {
                RoundedRectangle(cornerRadius: PiperTheme.radius).strokeBorder(focused ? PiperTheme.accent : PiperTheme.rule, lineWidth: 1)
            }
        }
        .accessibilityLabel(title)
    }
}

private struct SectionPicker: View {
    let sections: [String]
    let current: String
    let moving: Bool
    let select: (String) -> Void
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(moving ? "Move to" : "Capture to").font(PiperTheme.ui(13, weight: .semibold)).padding(.bottom, 8)
            ForEach(sections, id: \.self) { section in
                Button { select(section) } label: {
                    HStack {
                        Text(section)
                        Spacer()
                        if section == current { Text("current").foregroundStyle(PiperTheme.secondary) }
                    }
                    .font(PiperTheme.ui(13))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(section == current ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if !moving {
                HStack(spacing: 8) {
                    PiperField(title: "New section", text: $name, hint: "Return creates")
                        .onSubmit { if !trimmed.isEmpty { create() } }
                    Button("Create", action: create).buttonStyle(PiperButtonStyle()).disabled(trimmed.isEmpty)
                }.padding(.top, 10)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PiperButtonStyle()).keyboardShortcut(.cancelAction)
            }.padding(.top, 14)
        }
        .padding(22).frame(width: 400)
        .background(PiperTheme.page).foregroundStyle(PiperTheme.ink)
    }

    private func create() {
        select(sections.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed)
    }
}

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
            if cancel == nil {
                Text("Edit Note").font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary).frame(height: 38)
                Rule()
            }
            TextEditor(text: $session.text).font(Font(PiperTheme.manuscript(size: 14))).lineSpacing(5)
                .scrollContentBackground(.hidden).background(PiperTheme.page)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .accessibilityLabel("Edit note text")
                .frame(minHeight: 180)
            Rule()
            HStack(spacing: 8) {
                if let error = model.store.errorMessage {
                    Text(error).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.danger).textSelection(.enabled).lineLimit(2)
                } else {
                    Text(session.hasChanges ? "Unsaved changes" : "No changes").font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
                }
                Spacer()
                Button("Cancel") { if let cancel { cancel() } else { dismiss() } }
                    .buttonStyle(PiperButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save Changes", action: save).buttonStyle(PiperButtonStyle(prominent: true))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 480, height: cancel == nil ? 320 : nil)
        .background(PiperTheme.page)
        .foregroundStyle(PiperTheme.ink)
        .tint(PiperTheme.accent)
        .accentColor(PiperTheme.accent)
        .interactiveDismissDisabled(session.hasChanges)
        .onDisappear { model.captureEdits.removeValue(forKey: session.id) }
    }
}
