import Stream
import SwiftUI

/// One searchable list of the places that File puts items: the capture
/// sections, the folders, where an item becomes a new file, and the Markdown
/// files of the active folder, where it goes at the end.
struct FilePicker: View {
    let today: TodayModel
    let items: [StreamItem]

    @State private var query = ""
    @State private var cursor = 0
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var targets: [FileTarget] { today.fileTargets(query: query) }

    var body: some View {
        let targets = self.targets
        VStack(alignment: .leading, spacing: 0) {
            Text(items.count == 1 ? "File “\(String(items[0].title.prefix(40)))”" : "File \(items.count) Items")
                .font(PiperTheme.paperUI(.body, weight: .semibold))
                .lineLimit(1)
                .padding(.bottom, Metrics.titleBottom)
            TextField("Search sections and folders", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { pick(targets) }
                .onKeyPress(.downArrow) { cursor = min(cursor + 1, max(targets.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { cursor = max(cursor - 1, 0); return .handled }
                .accessibilityLabel("Search sections and folders")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(targets.enumerated()), id: \.element) { index, target in
                            if index == 0 || header(of: targets[index - 1]) != header(of: target) {
                                Text(header(of: target))
                                    .font(PiperTheme.paperUI(.body, weight: .semibold))
                                    .foregroundStyle(PiperTheme.paperMuted)
                                    .padding(.top, Metrics.headerTop).padding(.bottom, Metrics.headerBottom)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            row(target, on: index == cursor) {
                                cursor = index
                                pick(targets)
                            }
                            .id(index)
                        }
                    }
                }
                .onChange(of: cursor) { _, index in proxy.scrollTo(index) }
            }
            .overlay {
                if targets.isEmpty { PaperEmpty(symbol: "magnifyingglass", title: "No Places", detail: "Try another word.") }
            }
            HStack {
                Text("↑↓ choose · ↵ file").font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("File") { pick(targets) }.keyboardShortcut(.defaultAction).disabled(targets.isEmpty)
            }
            .padding(.top, Metrics.footTop)
        }
        .padding(Metrics.pickerPadding)
        .frame(width: FilePicker.Metrics.pickerSize.width, height: FilePicker.Metrics.pickerSize.height)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in cursor = 0 }
    }

    private func header(of target: FileTarget) -> String {
        switch target {
        case .section: return "Sections"
        case .folder: return "Folders · save as a file"
        case .file: return "Files · add to the end"
        }
    }

    private func row(_ target: FileTarget, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(target.title).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(target.detail).foregroundStyle(PickRow.secondary(on, otherwise: PiperTheme.paperFaint))
            }
            .font(PiperTheme.paperUI(.body))
            .pickRow(chosen: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(target.title), \(target.detail)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func pick(_ targets: [FileTarget]) {
        guard targets.indices.contains(cursor) else { return }
        if today.file(items, to: targets[cursor]) { today.filing = [] }
    }
}

extension FilePicker {
    enum Metrics {
        static let pickerSize = NSSize(width: 360, height: 380)
        static let pickerPadding: CGFloat = 16
        /// The space under the title of the sheet.
        static let titleBottom: CGFloat = 8
        /// The space over and under the header of a group of places.
        static let headerTop: CGFloat = 10
        static let headerBottom: CGFloat = 2
        /// The space over the row of the key hint and the buttons.
        static let footTop: CGFloat = 10
    }
}
