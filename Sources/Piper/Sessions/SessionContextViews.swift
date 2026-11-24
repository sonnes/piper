import Agents
import Captures
import Foundation
import PiperCore
import SwiftUI

/// The item on the screen beside a session: the open file, or the link or the
/// text of the open note.
struct ScreenItem: Equatable {
    let item: ContextItem
    /// The name in the `@` list, for example the title of an article.
    let title: String
}

/// The item on the screen, as the composer shows it.
struct ScreenContext: Equatable {
    let item: ContextItem
    let title: String
    /// True if the next message takes the item. False if the session has it.
    let pending: Bool
}

/// An item that the reader added with `@`, and the text after the `@`.
struct Mention: Equatable {
    let item: ContextItem
    let token: String
}

extension ContextItem {
    /// The short name of the item: a file name, a site and a path, or the first line of a note.
    var label: String {
        switch self {
        case .file(let path): return URL(fileURLWithPath: path).lastPathComponent
        case .link(let url):
            let host = Site(url)?.key ?? url.absoluteString
            let path = url.path()
            return path.count > 1 ? host + path : host
        case .note(let text):
            let line = CaptureText.firstLine(text)
            let limit = ContextMetrics.contextLabelLimit
            return line.count > limit ? String(line.prefix(limit)) + "…" : line
        }
    }

    /// Where the item is: the folder of a file, or the site of a link.
    var place: String {
        switch self {
        case .file(let path): return URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        case .link(let url): return Site(url)?.key ?? ""
        case .note: return ""
        }
    }

    var icon: String {
        switch self {
        case .file: return "doc.text"
        case .link: return "link"
        case .note: return "note.text"
        }
    }
}

/// One choice of the `@` list.
struct MentionOption: Identifiable, Equatable {
    enum Group: Equatable {
        case screen
        case files(String)
        case captures

        var title: String {
            switch self {
            case .screen: return "On the Screen"
            case .files(let folder): return "Files in \(folder)"
            case .captures: return "Captures"
            }
        }
    }

    let item: ContextItem
    let title: String
    /// The folder of a file, or the site or the section of a capture.
    let detail: String
    let group: Group
    /// The text that the composer puts after the `@`.
    let token: String

    var id: String { item.stored }

    /// The choices whose names hold the typed text: the item on the screen, then
    /// the files of the folder, then the captures that are not done.
    static func options(matching partial: String, screen: ScreenItem?, folder: String, files: [String],
                        notes: [Note]) -> [MentionOption] {
        let needle = partial.lowercased()
        func matches(_ values: String...) -> Bool {
            needle.isEmpty || values.contains { $0.lowercased().contains(needle) }
        }
        var options: [MentionOption] = []
        if let screen, matches(screen.title, screen.item.label) {
            options.append(MentionOption(item: screen.item, title: screen.title, detail: screen.item.place,
                                         group: .screen, token: token(screen.title)))
        }
        let folderName = URL(fileURLWithPath: folder).lastPathComponent
        for path in files where matches(path) {
            let item = ContextItem.file(URL(fileURLWithPath: folder).appendingPathComponent(path).path)
            guard !options.contains(where: { $0.item == item }) else { continue }
            options.append(MentionOption(item: item, title: (path as NSString).lastPathComponent,
                                         detail: (path as NSString).deletingLastPathComponent,
                                         group: .files(folderName), token: path))
            if options.count(where: { $0.group == .files(folderName) }) == ContextMetrics.fileCompletionLimit { break }
        }
        var captures = 0
        for note in notes where note.parent == nil && !note.isDone {
            let item: ContextItem
            let title: String
            let detail: String
            if note.isArticle, let url = note.articleURL {
                item = .link(url)
                title = note.reading?.title.map(CaptureText.firstLine) ?? item.label
                detail = Site(url)?.key ?? ""
            } else {
                item = .note(note.text)
                title = CaptureText.firstLine(note.text)
                detail = note.section
            }
            guard matches(title, detail), !options.contains(where: { $0.item == item }) else { continue }
            options.append(MentionOption(item: item, title: title, detail: detail, group: .captures, token: token(title)))
            captures += 1
            if captures == ContextMetrics.captureCompletionLimit { break }
        }
        return options
    }

    /// The title, cut to a short mention.
    private static func token(_ title: String) -> String {
        let limit = ContextMetrics.contextLabelLimit
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > limit ? String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : trimmed
    }
}

/// The files of a folder as relative paths, for the `@` list of a session in a
/// folder that is not on the Folders index.
enum FolderFileList {
    static func paths(in folder: String) -> [String] {
        let root = URL(fileURLWithPath: folder)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var paths: [String] = []
        let prefix = root.standardizedFileURL.path + "/"
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(prefix) { paths.append(String(path.dropFirst(prefix.count))) }
            if paths.count == ContextMetrics.folderFileLimit { break }
        }
        return paths.sorted()
    }
}

/// The `@` list over the composer, in groups.
struct MentionCompletions: View {
    let options: [MentionOption]
    let selected: Int
    let choose: (MentionOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                if index == 0 || options[index - 1].group != option.group {
                    CompletionGroupHeader(title: option.group.title, isFirst: index == 0)
                }
                row(option, active: index == selected)
            }
        }
        .modifier(CompletionListChrome())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context")
    }

    private func row(_ option: MentionOption, active: Bool) -> some View {
        Button { choose(option) } label: {
            HStack(spacing: ContextMetrics.rowSpacing) {
                Image(systemName: option.item.icon).frame(width: ContextMetrics.iconWidth)
                Text(option.title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: ContextMetrics.detailGap)
                Text(option.detail)
                    .font(PiperTheme.paperUI(.body))
                    .foregroundStyle(PickRow.secondary(active, otherwise: PiperTheme.paperFaint))
                    .lineLimit(1).truncationMode(.head)
            }
            .font(PiperTheme.paperUI(.body))
            .pickRow(chosen: active)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// A context item over the message field. An indigo chip goes with the next
/// message. A gray chip is an item that the session has.
struct ContextChip: View {
    let item: ContextItem
    let pending: Bool
    /// Removes an indigo chip. Nil hides the x.
    var remove: (() -> Void)?
    /// Sends a gray chip again.
    var resend: (() -> Void)?

    var body: some View {
        HStack(spacing: ContextMetrics.chipSpacing) {
            Image(systemName: item.icon)
            Text(item.label).lineLimit(1).truncationMode(.middle)
            if !pending { Text("· in session").foregroundStyle(PiperTheme.paperFaint) }
            if pending, let remove {
                Button(action: remove) { Image(systemName: "xmark").font(.system(size: ContextMetrics.chipRemoveGlyph, weight: .bold)) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.label)")
            }
        }
        .font(PiperTheme.paperUI(.body))
        .foregroundStyle(pending ? PiperTheme.brand : PiperTheme.paperFaint)
        .padding(.horizontal, ContextMetrics.chipPadding).frame(height: ContextMetrics.chipHeight)
        .background {
            if pending {
                Capsule().fill(ContextMetrics.pendingChipFill)
            } else {
                Capsule().strokeBorder(PiperTheme.paperRule, lineWidth: ContextMetrics.chipRing)
            }
        }
        .contentShape(Capsule())
        .onTapGesture { if !pending { resend?() } }
        .help(pending ? "The next message names \(item.argument)"
                      : "The session has \(item.argument). Click to send it again.")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(pending ? [] : .isButton)
    }
}

private enum ContextMetrics {
    /// The number of files that the `@` list shows.
    static let fileCompletionLimit = 8
    static let captureCompletionLimit = 4
    /// The files that Piper reads for the `@` list of a folder that is not on the Folders index.
    static let folderFileLimit = 5000
    /// The characters of a note or a title in a context chip or a mention.
    static let contextLabelLimit = 40
    static let rowSpacing: CGFloat = 6
    static let iconWidth: CGFloat = 14
    /// The least space before the folder or the site of a row.
    static let detailGap: CGFloat = 4
    static let chipSpacing: CGFloat = 4
    static let chipRemoveGlyph: CGFloat = 8
    static let chipPadding: CGFloat = 7
    static let chipHeight: CGFloat = 20
    /// The ring of a chip that the session has.
    static let chipRing: CGFloat = 0.5
    static let pendingChipFill = PiperTheme.brand.opacity(0.1)
}
