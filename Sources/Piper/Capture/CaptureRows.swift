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

/// Names a new section. Return creates it and makes it the target of new notes.
struct NewSectionSheet: View {
    let sections: [String]
    let create: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing) {
            Text("New Section").font(PiperTheme.paperUI(.body, weight: .semibold))
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
        .padding(Metrics.padding).frame(width: Metrics.width)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        create(sections.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed)
    }
}

extension NewSectionSheet {
    enum Metrics {
        static let spacing: CGFloat = 10
        static let padding: CGFloat = 16
        static let width: CGFloat = 280
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
            TextEditor(text: $session.text).font(PiperTheme.paperUI(.row)).lineSpacing(Metrics.lineSpacing)
                .scrollContentBackground(.hidden)
                .padding(Metrics.textPadding)
                .accessibilityLabel("Edit note text")
                .frame(minHeight: Metrics.textMinimumHeight)
            Rule()
            HStack(spacing: Metrics.barSpacing) {
                if session.hasChanges {
                    Text("Edited").font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
                }
                Spacer()
                Button("Cancel") { if let cancel { cancel() } else { dismiss() } }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(Metrics.barPadding)
        }
        .frame(width: Metrics.width, height: cancel == nil ? Metrics.sheetHeight : nil)
        .background(PiperTheme.paper)
        .foregroundStyle(PiperTheme.paperInk)
        .tint(PiperTheme.brand)
        .interactiveDismissDisabled(session.hasChanges)
        .onDisappear { model.captureEdits.removeValue(forKey: session.id) }
    }
}

extension NoteEditor {
    enum Metrics {
        static let width: CGFloat = 480
        /// The height of the editor in a sheet. In a window, the editor fills the window.
        static let sheetHeight: CGFloat = 300
        /// The first size of the Edit Note window.
        static let windowSize = NSSize(width: width, height: 360)
        static let lineSpacing: CGFloat = 3
        static let textPadding = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        static let textMinimumHeight: CGFloat = 180
        /// The bar of the Save and the Cancel buttons.
        static let barSpacing: CGFloat = 8
        static let barPadding = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
    }
}
