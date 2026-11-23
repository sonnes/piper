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
                .padding(.bottom, 8)
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
                                    .foregroundStyle(PiperTheme.secondaryLabel)
                                    .padding(.top, 10).padding(.bottom, 2)
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
            .padding(.top, 10)
        }
        .padding(16)
        .frame(width: AppDefaults.Today.pickerSize.width, height: AppDefaults.Today.pickerSize.height)
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
                Text(target.detail).foregroundStyle(on ? PiperTheme.onAccent.opacity(0.8) : PiperTheme.paperFaint)
            }
            .font(PiperTheme.paperUI(.body))
            .foregroundStyle(on ? PiperTheme.onAccent : PiperTheme.paperInk)
            .padding(.horizontal, 8)
            .frame(height: AppDefaults.Today.pickerRowHeight)
            .background(on ? PiperTheme.brand : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
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
