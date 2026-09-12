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

private struct LargeButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 38)
            .padding(.horizontal, 12)
            .foregroundStyle(enabled ? (prominent ? PiperTheme.page : PiperTheme.ink) : PiperTheme.secondary)
            .background(prominent && enabled ? PiperTheme.accent : PiperTheme.surface, in: RoundedRectangle(cornerRadius: 3))
            .opacity(configuration.isPressed ? 0.75 : 1)
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
    @Environment(\.colorSchemeContrast) private var contrast

    private var matchingNotes: [Note] { store.sections.flatMap { store.visibleNotes(in: $0) } }
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
            if !model.accessibilityEnabled { capturePermission }
            noteList
            if !store.selection.isEmpty { selectionBar }
            composer
                .padding(.horizontal, 18)
            footer
        }
        .background(PiperTheme.page)
        .foregroundStyle(PiperTheme.ink)
        .tint(PiperTheme.accent)
        .accentColor(PiperTheme.accent)
        .sheet(item: $sheet) { item in
            switch item {
            case .sections(let moving):
                SectionPicker(sections: store.sections, moving: moving) { section in
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

    private var capturePermission: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cursorarrow.click").foregroundStyle(PiperTheme.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                Text("Capture text from other apps").font(.system(size: 12, weight: .medium))
                Text("Enable Accessibility to save a selection with \(model.captureShortcut).").font(.system(size: 11)).foregroundStyle(PiperTheme.secondary)
                Button("Enable Selection Capture") { model.requestAccessibility() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            Spacer(minLength: 0)
        }.padding(14).background(PiperTheme.surface, in: RoundedRectangle(cornerRadius: 3))
            .padding(.horizontal, 22).padding(.bottom, 16)
    }

    private var header: some View {
        HStack(spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(PiperTheme.secondary)
                TextField("Search", text: $store.query)
                    .textFieldStyle(.plain).focused($searching)
                    .accessibilityLabel("Search notes and sections")
                if store.query.isEmpty {
                    Text("⌘F").font(.system(size: 10)).foregroundStyle(PiperTheme.secondary).accessibilityHidden(true)
                } else {
                    Button { store.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(PiperTheme.secondary)
                    }.buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(PiperTheme.surface, in: RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .bottom) { Rectangle().fill(contrast == .increased ? PiperTheme.ink : PiperTheme.control).frame(height: 1) }
            Button { model.route = "wiki"; model.openLibrary?() } label: {
                Label("Wiki", systemImage: "books.vertical")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(PiperTheme.surface, in: RoundedRectangle(cornerRadius: 3))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Browse Wiki · ⌘2")
            .accessibilityLabel("Browse Wiki")
            Menu {
                Button("Capture Clipboard", systemImage: "doc.on.clipboard") { store.captureClipboard() }
                Button("Choose Section…", systemImage: "tray") { sheet = .sections(moving: false) }
                Divider()
                Button("Settings…", systemImage: "gearshape") { model.route = "settings"; model.openLibrary?() }
                Divider()
                Button("Undo Last Change", systemImage: "arrow.uturn.backward") { store.undo() }.disabled(!store.canUndo)
                Button("Close Capture") { (NSApp.keyWindow as? CapturePanel)?.orderOut(nil) }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .fixedSize().frame(width: 34, height: 34)
                .background(PiperTheme.surface, in: RoundedRectangle(cornerRadius: 3))
                .help("More Actions").accessibilityLabel("More Actions")
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 24)
    }

    private var noteList: some View {
        let sections = store.sections.filter { !store.visibleNotes(in: $0).isEmpty }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 23) {
                    if !clipboardEntries.isEmpty {
                        VStack(spacing: 0) {
                            HStack(spacing: 9) {
                                Text("CLIPBOARD").font(.system(size: 10, weight: .medium)).tracking(0.8)
                                    .accessibilityAddTraits(.isHeader)
                                Rectangle().fill(PiperTheme.ink.opacity(0.1)).frame(height: 1)
                                Text("Click to save").font(.system(size: 10))
                            }.foregroundStyle(PiperTheme.secondary).padding(.horizontal, 12).padding(.bottom, 12)
                            ForEach(clipboardEntries) { entry in
                                ClipboardGhostCard(entry: entry, section: store.activeSection) {
                                    withAnimation(motion) {
                                        if model.clipboard.save(entry.id) {
                                            store.selection.removeAll()
                                            selectionAnchor = nil
                                        }
                                    }
                                }.id(entry.id).transition(.opacity)
                            }
                        }
                    }
                    ForEach(sections, id: \.self) { section in
                        VStack(spacing: 0) {
                            HStack(spacing: 9) {
                                Text(section.uppercased())
                                    .font(.system(size: 10, weight: .medium))
                                    .tracking(0.8)
                                    .foregroundStyle(PiperTheme.secondary)
                                    .lineLimit(1)
                                    .accessibilityAddTraits(.isHeader)
                                Rectangle().fill(PiperTheme.ink.opacity(0.1)).frame(height: 1)
                            }
                            .padding(.horizontal, 12).padding(.bottom, 8)
                            ForEach(store.visibleNotes(in: section)) { note in
                                CaptureNoteCard(note: note, selected: store.selection.contains(note.id),
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
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
            .overlay {
                if sections.isEmpty && clipboardEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: store.query.isEmpty ? "text.cursor" : "magnifyingglass")
                            .font(.system(size: 26, weight: .light)).foregroundStyle(PiperTheme.secondary)
                        Text(store.query.isEmpty ? "Keep the useful parts" : "No matching notes")
                            .font(.system(size: 15, weight: .medium))
                        if store.query.isEmpty {
                            Text("Select text in another app, then press")
                                .font(.system(size: 12)).foregroundStyle(PiperTheme.secondary)
                            Text(model.captureShortcut == "Shift, Shift" ? "⇧  ⇧" : "⌃ ⌥ C")
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(PiperTheme.surface, in: RoundedRectangle(cornerRadius: 3))
                                .accessibilityLabel(model.captureShortcut)
                            Text("Or add a note below.")
                                .font(.system(size: 12)).foregroundStyle(PiperTheme.secondary).padding(.top, 3)
                        } else {
                            Text("Try another word or section name.")
                                .font(.system(size: 12)).foregroundStyle(PiperTheme.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .allowsHitTesting(false)
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
        }
        .frame(maxHeight: .infinity)
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Button { store.selection.removeAll() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "xmark.circle.fill")
                    Text("\(store.selection.count) selected")
                }.foregroundStyle(PiperTheme.secondary)
            }.buttonStyle(.plain).accessibilityLabel("Clear selection")
            Spacer(minLength: 0)
            Menu {
                Button("Copy", action: { store.copy(asList: false) })
                Button("Mark as Done / Reopen") { store.completeSelection() }
                Button("Merge Notes") { store.merge() }.disabled(store.selection.count < 2)
                Button("Move to Section…") { sheet = .sections(moving: true) }
                Button("Send to Wiki") { model.prepareExport(); sheet = .export }
                Divider()
                Button("Delete Notes", role: .destructive) { store.deleteSelection() }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .frame(width: 26, height: 28).accessibilityLabel("Selected note actions")
            Button { store.copy(asList: true) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.number")
                    Text("Copy as List")
                }
            }.buttonStyle(.borderedProminent).foregroundStyle(PiperTheme.page).controlSize(.small)
                .help("Copy as List · ⇧⌘C")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 26)
        .padding(.bottom, 12)
    }

    private var composer: some View {
        CaptureEditor(text: $draft, focused: $composing)
        .frame(height: 104)
        .background(PiperTheme.page, in: RoundedRectangle(cornerRadius: 3))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(composing ? PiperTheme.accent : (contrast == .increased ? PiperTheme.ink : PiperTheme.control), lineWidth: composing ? 2 : 1)
        }
        .animation(motion, value: composing)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if store.status == "Local notes" {
                Text(model.captureShortcut == "Shift, Shift" ? "⇧ ⇧" : "⌃⌥C")
                    .fontWeight(.medium).accessibilityLabel(model.captureShortcut)
                Text("Capture selected text")
            } else {
                Text(store.status).lineLimit(1).help(store.status)
            }
            Spacer(minLength: 4)
            if store.canUndo {
                Button("Undo") { store.undo() }.buttonStyle(.plain).help("Undo Last Change")
            }
        }
        .font(.system(size: 10)).foregroundStyle(PiperTheme.secondary)
        .padding(.horizontal, 32).padding(.top, 12).padding(.bottom, 25)
    }

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

private struct ClipboardGhostCard: View {
    let entry: ClipboardEntry
    let section: String
    let save: () -> Void
    @State private var hovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: save) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 19, height: 19)
                    Image(systemName: "plus").font(.system(size: 9, weight: .medium))
                }.frame(width: 24, height: 24)
                    .foregroundStyle(hovered ? PiperTheme.accent : PiperTheme.secondary)
                    .accessibilityHidden(true)
                Text(entry.text)
                    .font(Font(PiperTheme.manuscript(size: 15))).lineSpacing(5).lineLimit(4)
                    .foregroundStyle(hovered || contrast == .increased ? PiperTheme.ink : PiperTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
            .padding(16)
            .background(hovered ? PiperTheme.selection : PiperTheme.surface, in: RoundedRectangle(cornerRadius: 3))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(hovered ? PiperTheme.accent : (contrast == .increased ? PiperTheme.ink : PiperTheme.control), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .contentShape(Rectangle())
            .padding(.bottom, 10)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Save to \(section)")
        .accessibilityLabel("Save clipboard item: \(String(entry.text.prefix(240)))")
        .accessibilityHint("Saves this item to \(section). Clipboard previews are unsaved.")
    }
}

private struct CaptureNoteCard: View {
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
    @Environment(\.colorSchemeContrast) private var contrast

    private var formattedText: AttributedString {
        (try? AttributedString(markdown: note.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(note.text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: complete) {
                Image(systemName: note.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(note.isDone ? PiperTheme.success : PiperTheme.secondary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(note.isDone ? "Reopen note" : "Mark note as done")
            Button(action: select) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(formattedText)
                        .font(Font(PiperTheme.manuscript(size: 15))).lineSpacing(5).lineLimit(4)
                        .strikethrough(note.isDone)
                        .foregroundStyle(note.isDone ? PiperTheme.secondary : PiperTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let source = note.sources.first {
                        Label(source, systemImage: "arrow.up.right")
                            .font(.system(size: 10)).foregroundStyle(PiperTheme.secondary).lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("Command-click adds to the selection. Return edits the note.")
        }
        .padding(.horizontal, 12).padding(.vertical, 17)
        .background(selected ? PiperTheme.selection : PiperTheme.page)
        .overlay(alignment: .bottom) { Rectangle().fill(contrast == .increased ? PiperTheme.control : PiperTheme.rule).frame(height: 1) }
        .overlay(alignment: .leading) { if selected { Rectangle().fill(PiperTheme.accent).frame(width: 2) } }
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

private struct SectionPicker: View {
    let sections: [String]
    let moving: Bool
    let select: (String) -> Void
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(moving ? "Move Notes" : "Choose a Section").font(.headline)
            ForEach(sections, id: \.self) { section in
                Button { select(section) } label: { Label(section, systemImage: "number") }
            }
            if !moving {
                HStack {
                    TextField("New section name", text: $name).textFieldStyle(.roundedBorder)
                    Button("Create") {
                        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        select(sections.first { $0.caseInsensitiveCompare(value) == .orderedSame } ?? value)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(width: 80)
                }
            }
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(24).frame(width: 390)
        .buttonStyle(LargeButtonStyle())
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Note").font(.headline)
            TextEditor(text: $session.text).font(Font(PiperTheme.manuscript(size: 15)))
                .scrollContentBackground(.hidden).background(PiperTheme.page)
                .accessibilityLabel("Edit note text").frame(height: 180)
            if let error = model.store.errorMessage {
                Text(error).font(.caption).foregroundStyle(PiperTheme.danger).textSelection(.enabled)
            }
            HStack {
                Button("Cancel") { if let cancel { cancel() } else { dismiss() } }.keyboardShortcut(.cancelAction)
                Button("Save Changes", action: save).buttonStyle(LargeButtonStyle(prominent: true))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 430)
        .background(PiperTheme.page)
        .foregroundStyle(PiperTheme.ink)
        .tint(PiperTheme.accent)
        .accentColor(PiperTheme.accent)
        .buttonStyle(LargeButtonStyle())
        .interactiveDismissDisabled(session.hasChanges)
        .onDisappear { model.captureEdits.removeValue(forKey: session.id) }
    }
}
