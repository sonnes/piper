import Foundation
import PiperCore
import Vault

struct WikiLocation: Equatable {
    let path: String
    var anchor: String? = nil
}

struct WikiWorkspace {
    var history: [WikiLocation] = []
    var position = 0
    var location: WikiLocation? { history.indices.contains(position) ? history[position] : nil }
    var canGoBack: Bool { position > 0 }
    var canGoForward: Bool { position + 1 < history.count }

    mutating func open(_ location: WikiLocation) {
        guard location != self.location else { return }
        history = Array(history.prefix(history.isEmpty ? 0 : position + 1)) + [location]
        position = history.count - 1
    }

    mutating func move(_ offset: Int) {
        let next = position + offset
        guard history.indices.contains(next) else { return }
        position = next
    }

    mutating func reconcile(paths: Set<String>) {
        let preceding = history.prefix(position).filter { paths.contains($0.path) }.count
        history.removeAll { !paths.contains($0.path) }
        position = max(0, min(preceding, history.count - 1))
    }
}

enum WikiLinks {
    static func resolve(_ target: String, from document: VaultFile, files: [VaultFile], vault: Vault, wikiStyle: Bool = false) throws -> WikiLocation {
        let parts = target.components(separatedBy: "#")
        let path = (parts.first ?? "").removingPercentEncoding ?? parts.first ?? ""
        let anchor = parts.count > 1 ? parts.dropFirst().joined(separator: "#").removingPercentEncoding : nil
        if path.isEmpty { return WikiLocation(path: document.id, anchor: anchor) }
        let file = (path as NSString).pathExtension.isEmpty ? path + ".md" : path
        let relative = try vault.containedURL(file, relativeTo: document.relativePath)
        let relativePath = String(relative.path.dropFirst(vault.root.path.count + 1))
        if files.contains(where: { $0.id == relativePath }) { return WikiLocation(path: relativePath, anchor: anchor) }
        if wikiStyle {
            let rooted = try vault.containedURL("/" + file.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            let rootedPath = String(rooted.path.dropFirst(vault.root.path.count + 1))
            if files.contains(where: { $0.id == rootedPath }) { return WikiLocation(path: rootedPath, anchor: anchor) }
            let candidates = files.filter {
                $0.title.caseInsensitiveCompare(path) == .orderedSame ||
                URL(fileURLWithPath: $0.id).deletingPathExtension().lastPathComponent.caseInsensitiveCompare(path) == .orderedSame
            }
            if candidates.count == 1 { return WikiLocation(path: candidates[0].id, anchor: anchor) }
            if candidates.count > 1 { throw PiperError("More than one note matches “\(path)”. Use the folder path in the link.") }
        }
        throw PiperError("The note “\(path)” is unavailable in this Wiki.")
    }

    static func targets(in text: String) -> [(target: String, wikiStyle: Bool)] {
        let blocks = WikiMarkdown.parse(text).filter { $0.kind != .code }
        let text = blocks.map(\.text).joined(separator: "\n").replacingOccurrences(of: "`[^`]*`", with: "", options: .regularExpression)
        let pattern = #"(?<!!)\[\[([^\]|]+)(?:\|[^\]]+)?\]\]|(?<!!)\[[^\]]+\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            if let range = Range(match.range(at: 1), in: text) { return (String(text[range]), true) }
            if let range = Range(match.range(at: 2), in: text) { return (String(text[range]), false) }
            return nil
        }
    }

    static func backlinks(to document: VaultFile, in files: [VaultFile], vault: Vault) -> [VaultFile] {
        files.filter { source in
            source.id != document.id && targets(in: source.body).contains { link in
                guard URL(string: link.target)?.scheme == nil else { return false }
                return (try? resolve(link.target, from: source, files: files, vault: vault, wikiStyle: link.wikiStyle))?.path == document.id
            }
        }
    }
}
