import AppKit
import SwiftUI
import Agents
import Captures

/// A short time for a row: the clock time today, and the date before today.
enum RowTime {
    static func text(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: Menus

/// The context menu of a capture row in Inbox.
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
