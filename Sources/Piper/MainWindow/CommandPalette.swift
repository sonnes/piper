import AppKit
import PiperCore
import SwiftUI
import Vault

/// A command that the palette lists, with the shortcut of its menu item.
struct PaletteCommand: Identifiable {
    var id: String { title }
    let title: String
    let shortcut: String
    let run: () -> Void
}

/// The command palette over the main window: Go > Go to File, Command-K.
///
/// The design copies the palette of Hubble.md. Text finds files by name, text
/// of three characters or more also finds lines in files, and text that starts
/// with `/` lists the commands.
@MainActor
final class CommandPaletteController {
    private var panel: PalettePanel?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func toggle(over window: NSWindow, commands: [PaletteCommand], open: @escaping (String) -> Void) {
        if let panel, panel.isVisible {
            close()
            return
        }
        let panel = PalettePanel(contentRect: NSRect(origin: .zero, size: AppDefaults.Palette.size),
                                 styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.onResign = { [weak self] in self?.close() }
        let view = CommandPaletteView(model: model, commands: commands, open: { [weak self] path in
            self?.close()
            open(path)
        }, run: { [weak self] command in
            self?.close()
            PaletteRecents.add(command.title)
            command.run()
        }, close: { [weak self] in self?.close() })
        panel.contentView = NSHostingView(rootView: view)
        let frame = window.frame
        panel.setFrameOrigin(NSPoint(x: frame.midX - AppDefaults.Palette.size.width / 2,
                                     y: frame.maxY - AppDefaults.Palette.topInset - AppDefaults.Palette.size.height))
        window.addChildWindow(panel, ordered: .above)
        panel.makeKey()
        self.panel = panel
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.onResign = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}

/// A borderless panel that takes the keyboard, and closes when it loses it.
private final class PalettePanel: NSPanel {
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

/// The commands that the reader ran last, newest first.
enum PaletteRecents {
    static func titles(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: AppDefaults.Key.paletteRecents) ?? []
    }

    static func add(_ title: String, _ defaults: UserDefaults = .standard) {
        var titles = titles(defaults).filter { $0 != title }
        titles.insert(title, at: 0)
        defaults.set(Array(titles.prefix(AppDefaults.Palette.recentLimit)), forKey: AppDefaults.Key.paletteRecents)
    }
}

/// The rows of the palette for a query. The view and the tests share it.
struct PaletteResults {
    enum Row: Identifiable {
        case file(VaultFile)
        case line(VaultFile, PaletteSearch.Excerpt)
        case command(PaletteCommand)

        var id: String {
            switch self {
            case .file(let file): return "file:" + file.id
            case .line(let file, let excerpt): return "line:\(file.id):\(excerpt.line)"
            case .command(let command): return "command:" + command.title
            }
        }
    }

    var files: [Row] = []
    var lines: [Row] = []
    var commands: [Row] = []
    var all: [Row] { files + lines + commands }

    /// Ranks the files and the commands. `recent` lists the files to show first for an empty query.
    static func rank(_ query: String, files: [VaultFile], recent: [String], commands: [PaletteCommand],
                     recentCommands: [String]) -> PaletteResults {
        var results = PaletteResults()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") {
            let text = String(trimmed.dropFirst())
            results.commands = rankCommands(text, commands, recent: recentCommands).map(Row.command)
            return results
        }
        if trimmed.isEmpty {
            let byID = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            results.files = recent.compactMap { byID[$0] }.prefix(AppDefaults.Palette.fileLimit).map(Row.file)
            return results
        }
        var scored: [(file: VaultFile, score: Double)] = []
        for file in files {
            let score = PaletteSearch.score(trimmed, path: file.id, title: file.title)
            if score > 0 { scored.append((file, score)) }
        }
        scored.sort { first, second in
            if first.score != second.score { return first.score > second.score }
            return first.file.id.localizedStandardCompare(second.file.id) == .orderedAscending
        }
        results.files = scored.prefix(AppDefaults.Palette.fileLimit).map { Row.file($0.file) }
        results.commands = rankCommands(trimmed, commands, recent: recentCommands)
            .filter { PaletteSearch.score(trimmed, $0.title) >= 0.75 }
            .prefix(AppDefaults.Palette.commandLimit)
            .map(Row.command)
        return results
    }

    /// The lines in the text files that hold the query.
    nonisolated static func lines(_ query: String, in files: [VaultFile]) -> [Row] {
        var rows: [Row] = []
        var fileCount = 0
        for file in files where file.isText {
            guard fileCount < PaletteSearch.contentFileLimit else { break }
            let excerpts = PaletteSearch.excerpts(of: query, in: file.body)
            if excerpts.isEmpty { continue }
            fileCount += 1
            rows += excerpts.map { Row.line(file, $0) }
        }
        return rows
    }

    private static func rankCommands(_ query: String, _ commands: [PaletteCommand], recent: [String]) -> [PaletteCommand] {
        var scored: [(command: PaletteCommand, score: Double, recency: Int)] = []
        for command in commands {
            let score = PaletteSearch.score(query, command.title)
            if score > 0 { scored.append((command, score, recent.firstIndex(of: command.title) ?? Int.max)) }
        }
        scored.sort { first, second in
            if first.score != second.score { return first.score > second.score }
            return first.recency < second.recency
        }
        return scored.map(\.command)
    }
}

private struct CommandPaletteView: View {
    let model: AppModel
    let commands: [PaletteCommand]
    let open: (String) -> Void
    let run: (PaletteCommand) -> Void
    let close: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @State private var lines: [PaletteResults.Row] = []
    @FocusState private var focused: Bool

    private var results: PaletteResults {
        var results = PaletteResults.rank(query, files: model.files,
                                          recent: model.workspace.history.reversed().map(\.path),
                                          commands: commands, recentCommands: PaletteRecents.titles())
        results.lines = lines
        return results
    }

    var body: some View {
        let results = results
        let rows = results.all
        VStack(spacing: 0) {
            TextField("Go to file, or type / for commands", text: $query)
                .textFieldStyle(.plain)
                .font(PiperTheme.ui(AppDefaults.Palette.queryFontSize))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .focused($focused)
                .onKeyPress(.downArrow) { move(1, in: rows); return .handled }
                .onKeyPress(.upArrow) { move(-1, in: rows); return .handled }
                .onKeyPress(.escape) { close(); return .handled }
                .onSubmit { choose(rows.indices.contains(selection) ? rows[selection] : nil) }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        section("Files", results.files, offset: 0)
                        section("Lines", results.lines, offset: results.files.count)
                        section("Commands", results.commands, offset: results.files.count + results.lines.count)
                        if rows.isEmpty {
                            Text(query.isEmpty ? "Type to find a file." : "No results")
                                .foregroundStyle(PiperTheme.secondary)
                                .padding(14)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: selection) { _, value in
                    if rows.indices.contains(value) { proxy.scrollTo(rows[value].id) }
                }
            }
        }
        .frame(width: AppDefaults.Palette.size.width, height: AppDefaults.Palette.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.Palette.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppDefaults.Palette.cornerRadius).strokeBorder(.separator))
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .task(id: query) {
            lines = []
            let text = query.trimmingCharacters(in: .whitespaces)
            guard text.count >= PaletteSearch.minimumQueryLength, !text.hasPrefix("/") else { return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let files = model.files
            let found = await Task.detached { PaletteResults.lines(text, in: files) }.value
            if !Task.isCancelled { lines = found }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [PaletteResults.Row], offset: Int) -> some View {
        if !rows.isEmpty {
            Text(title)
                .font(PiperTheme.ui(.caption, weight: .semibold))
                .foregroundStyle(PiperTheme.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 3)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                PaletteRow(row: row, selected: offset + index == selection)
                    .id(row.id)
                    .contentShape(Rectangle())
                    .onTapGesture { choose(row) }
            }
        }
    }

    private func move(_ step: Int, in rows: [PaletteResults.Row]) {
        guard !rows.isEmpty else { return }
        selection = (selection + step + rows.count) % rows.count
    }

    private func choose(_ row: PaletteResults.Row?) {
        switch row {
        case .file(let file): open(file.id)
        case .line(let file, _): open(file.id)
        case .command(let command): run(command)
        case nil: break
        }
    }
}

private struct PaletteRow: View {
    let row: PaletteResults.Row
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(selected ? Color.white : PiperTheme.secondary)
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                Text(detail)
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : PiperTheme.secondary)
            }
            if case .line(_, let excerpt) = row {
                Text(highlighted(excerpt))
                    .lineLimit(1)
                    .font(PiperTheme.ui(.secondary))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : PiperTheme.secondary)
                    .padding(.leading, 24)
            }
        }
        .font(PiperTheme.ui(.body))
        .foregroundStyle(selected ? Color.white : PiperTheme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(selected ? PiperTheme.accent : Color.clear)
    }

    private var icon: String {
        switch row {
        case .file: return "doc.text"
        case .line: return "text.magnifyingglass"
        case .command: return "command"
        }
    }

    private var title: String {
        switch row {
        case .file(let file), .line(let file, _): return file.title
        case .command(let command): return command.title
        }
    }

    private var detail: String {
        switch row {
        case .file(let file), .line(let file, _):
            let folder = (file.id as NSString).deletingLastPathComponent
            return folder.isEmpty ? "" : folder
        case .command(let command): return command.shortcut
        }
    }

    private func highlighted(_ excerpt: PaletteSearch.Excerpt) -> AttributedString {
        var text = AttributedString(excerpt.text)
        if let lower = AttributedString.Index(excerpt.match.lowerBound, within: text),
           let upper = AttributedString.Index(excerpt.match.upperBound, within: text) {
            text[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }
}
