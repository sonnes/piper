import AppKit
import SwiftUI
import Captures

// MARK: Tabs and headers

/// One tab in the header of the capture panel.
struct PanelTab: View {
    let title: String
    let icon: String?
    let count: Int
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 11)) }
                Text(title).lineLimit(1)
                if count > 0 {
                    Text("\(count)").font(PiperTheme.ui(11)).monospacedDigit()
                        .foregroundStyle(active ? PiperTheme.secondary : PiperTheme.faint)
                }
            }
            .font(PiperTheme.ui(12.5, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? PiperTheme.ink : PiperTheme.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(active ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
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
            Text(title).font(PiperTheme.ui(13, weight: .semibold))
                .foregroundStyle(active ? PiperTheme.accent : PiperTheme.ink)
            if let detail {
                Text(detail).font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
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
            .font(PiperTheme.ui(11, weight: .semibold))
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
        VStack(spacing: 0) { content }
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
    @State private var hovered = false
    private var isCode: Bool { CaptureText.looksLikeCode(entry.text) }

    var body: some View {
        VStack(spacing: 0) {
            if separated { RowSeparator(inset: AppDefaults.CaptureItem.horizontalPadding + 22) }
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12))
                    .foregroundStyle(PiperTheme.faint)
                    .frame(width: 12)
                Text(isCode ? CaptureText.firstLine(entry.text) : entry.text.replacingOccurrences(of: "\n", with: " "))
                    .font(isCode
                          ? Font(PiperTheme.manuscript(size: AppDefaults.CaptureItem.clipboardCodeFontSize))
                          : PiperTheme.ui(AppDefaults.CaptureItem.clipboardFontSize))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hovered {
                    Button("Keep", action: keep).controlSize(.small).help("Save to Inbox")
                }
                if showsSource, let source = entry.source {
                    Text(source).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint).lineLimit(1).fixedSize()
                }
                Text(RowTime.text(entry.copiedAt))
                    .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.faint).monospacedDigit().fixedSize()
            }
            .padding(.horizontal, AppDefaults.CaptureItem.horizontalPadding)
            .frame(minHeight: AppDefaults.CaptureItem.clipboardHeight)
            .background(hovered ? PiperTheme.hover : .clear)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(count: 2, perform: paste)
        .contextMenu {
            Button("Paste", systemImage: "doc.on.clipboard", action: paste)
            Button("Keep in Inbox", systemImage: "tray.and.arrow.down", action: keep)
        }
        .help(String(entry.text.prefix(500)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clipboard: \(String(entry.text.prefix(240)))")
        .accessibilityAction(named: "Keep in Inbox", keep)
        .accessibilityAction(named: "Paste", paste)
    }
}

/// One saved note.
struct NoteRow: View {
    let note: Note
    let selected: Bool
    let separated: Bool
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

    private var link: URL? { CaptureLinks(note.text).standaloneURL }

    private var formattedText: AttributedString {
        (try? AttributedString(markdown: note.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(note.text)
    }

    /// The application a note came from, when a selection capture recorded it.
    private var source: String? {
        guard let source = note.sources.first, source != "Clipboard", link == nil else { return nil }
        return "From " + source
    }

    var body: some View {
        VStack(spacing: 0) {
            if separated && !selected { RowSeparator(inset: AppDefaults.CaptureItem.textInset) }
            HStack(alignment: .center, spacing: 10) {
                Button(action: complete) {
                    Circle()
                        .strokeBorder(note.isDone ? .clear : PiperTheme.faint, lineWidth: 1.25)
                        .background(Circle().fill(note.isDone ? PiperTheme.accent : .clear))
                        .overlay {
                            if note.isDone {
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            }
                        }
                        .frame(width: AppDefaults.CaptureItem.circleSize, height: AppDefaults.CaptureItem.circleSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(note.isDone ? "Reopen note" : "Mark note as done")
                Button(action: select) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            if let link {
                                Text((link.host() ?? "") + link.path())
                                    .foregroundStyle(note.isDone ? PiperTheme.secondary : PiperTheme.accent)
                                    .lineLimit(1).truncationMode(.middle)
                            } else {
                                Text(formattedText)
                                    .foregroundStyle(note.isDone ? PiperTheme.secondary : PiperTheme.ink)
                                    .lineSpacing(AppDefaults.CaptureItem.lineSpacing)
                                    .lineLimit(3)
                            }
                            if let source {
                                Text(source).font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary).lineLimit(1)
                            }
                        }
                        .font(PiperTheme.ui(AppDefaults.CaptureItem.fontSize))
                        .strikethrough(note.isDone, color: PiperTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(RowTime.text(note.createdAt))
                            .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.faint).monospacedDigit().fixedSize()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint("Command-click adds to the selection. Return edits the note.")
            }
            .padding(.horizontal, AppDefaults.CaptureItem.horizontalPadding)
            .padding(.vertical, AppDefaults.CaptureItem.verticalPadding)
            .frame(minHeight: AppDefaults.CaptureItem.minimumHeight)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: PiperTheme.cardRadius)
                        .strokeBorder(PiperTheme.accent, lineWidth: 2)
                }
            }
        }
        .contextMenu {
            Button("Copy") { copy(false) }
            Button("Copy as List") { copy(true) }
            Divider()
            Button(note.isDone ? "Reopen" : "Mark as Done", action: complete)
            Button("Edit", action: edit)
            Button("Edit in New Window", action: newWindow)
            Divider()
            Button("Merge Notes", action: merge).disabled(!canMerge)
            Button("Move To…") { prepareActions(); move() }
            if let source = note.sourceURLs.first, let url = URL(string: source), CaptureLinks.isWebURL(url) {
                Divider()
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
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
            Text(moving ? "Move To" : "Capture To").font(PiperTheme.ui(13, weight: .semibold))
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
            .font(PiperTheme.ui(13))
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
            Text("New Section").font(PiperTheme.ui(13, weight: .semibold))
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
            TextEditor(text: $session.text).font(PiperTheme.ui(15)).lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .accessibilityLabel("Edit note text")
                .frame(minHeight: 180)
            Rule()
            HStack(spacing: 8) {
                if let error = model.store.errorMessage {
                    Text(error).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.danger).textSelection(.enabled).lineLimit(2)
                } else if session.hasChanges {
                    Text("Edited").font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
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
