import Agents
import Captures
import Foundation
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
            let host = AppModel.siteKey(url) ?? url.absoluteString
            let path = url.path()
            return path.count > 1 ? host + path : host
        case .note(let text):
            let line = CaptureText.firstLine(text)
            let limit = AppDefaults.Sessions.contextLabelLimit
            return line.count > limit ? String(line.prefix(limit)) + "…" : line
        }
    }

    /// Where the item is: the folder of a file, or the site of a link.
    var place: String {
        switch self {
        case .file(let path): return URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        case .link(let url): return AppModel.siteKey(url) ?? ""
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
            if options.count(where: { $0.group == .files(folderName) }) == AppDefaults.Sessions.fileCompletionLimit { break }
        }
        var captures = 0
        for note in notes where note.parent == nil && !note.isDone {
            let item: ContextItem
            let title: String
            let detail: String
            if note.isArticle, let url = note.articleURL {
                item = .link(url)
                title = note.reading?.title.map(CaptureText.firstLine) ?? item.label
                detail = AppModel.siteKey(url) ?? ""
            } else {
                item = .note(note.text)
                title = CaptureText.firstLine(note.text)
                detail = note.section
            }
            guard matches(title, detail), !options.contains(where: { $0.item == item }) else { continue }
            options.append(MentionOption(item: item, title: title, detail: detail, group: .captures, token: token(title)))
            captures += 1
            if captures == AppDefaults.Sessions.captureCompletionLimit { break }
        }
        return options
    }

    /// The title, cut to a short mention.
    private static func token(_ title: String) -> String {
        let limit = AppDefaults.Sessions.contextLabelLimit
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > limit ? String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : trimmed
    }
}

/// The files of a folder as relative paths, for the `@` list of a session in a
/// folder that the sidebar does not show.
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
            if paths.count == AppDefaults.Sessions.folderFileLimit { break }
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
                    Text(option.group.title)
                        .font(PiperTheme.ui(.caption, weight: .semibold))
                        .foregroundStyle(PiperTheme.faint)
                        .padding(.horizontal, 8).padding(.top, index == 0 ? 4 : 8).padding(.bottom, 3)
                }
                row(option, active: index == selected)
            }
        }
        .padding(6)
        .background(PiperTheme.card, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context")
    }

    private func row(_ option: MentionOption, active: Bool) -> some View {
        Button { choose(option) } label: {
            HStack(spacing: 6) {
                Image(systemName: option.item.icon).frame(width: 14)
                Text(option.title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text(option.detail)
                    .font(PiperTheme.ui(.caption))
                    .foregroundStyle(active ? Color.white.opacity(0.8) : PiperTheme.faint)
                    .lineLimit(1).truncationMode(.head)
            }
            .font(PiperTheme.ui(.secondary))
            .foregroundStyle(active ? Color.white : PiperTheme.ink)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(active ? PiperTheme.accent : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// A context item over the message field. A blue chip goes with the next
/// message. A gray chip is an item that the session has.
struct ContextChip: View {
    let item: ContextItem
    let pending: Bool
    /// Removes a blue chip. Nil hides the x.
    var remove: (() -> Void)?
    /// Sends a gray chip again.
    var resend: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: item.icon)
            Text(item.label).lineLimit(1).truncationMode(.middle)
            if !pending { Text("· in session").foregroundStyle(PiperTheme.faint) }
            if pending, let remove {
                Button(action: remove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.label)")
            }
        }
        .font(PiperTheme.ui(.caption))
        .foregroundStyle(pending ? PiperTheme.accent : PiperTheme.faint)
        .padding(.horizontal, 7).frame(height: 20)
        .background {
            if pending {
                Capsule().fill(PiperTheme.accent.opacity(0.1))
            } else {
                Capsule().strokeBorder(PiperTheme.rule, lineWidth: 0.5)
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
