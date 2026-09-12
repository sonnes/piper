import Foundation
import Yams

struct WikiDocument: Identifiable {
    var id: String { relativePath }
    let relativePath: String
    let raw: String
    let body: String
    let metadata: [String: Any]
    let problem: String?
    var title: String { metadata["title"] as? String ?? URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent }
    var description: String { metadata["description"] as? String ?? "" }
    var folder: String { (relativePath as NSString).deletingLastPathComponent }
    var type: String { metadata["type"] as? String ?? "Document" }
    var status: String { metadata["status"] as? String ?? "" }
    var sources: [[String: Any]] { metadata["sources"] as? [[String: Any]] ?? [] }
    var captureIDs: Set<String> { Set(metadata["piper_capture_ids"] as? [String] ?? []) }
    var frontmatterPrefix: String {
        var first = true
        var end: String.Index?
        raw.enumerateSubstrings(in: raw.startIndex..., options: .byLines) { line, _, enclosingRange, stop in
            let delimiter = line?.trimmingCharacters(in: .whitespaces) == "---"
            if first { first = false; stop = !delimiter }
            else if delimiter { end = enclosingRange.upperBound; stop = true }
        }
        return end.map { String(raw[..<$0]) } ?? ""
    }
    var editableBody: String { String(raw.dropFirst(frontmatterPrefix.count)) }
    var verification: String {
        let entries = metadata["verified"] as? [[String: Any]] ?? (metadata["verified"] as? [String: Any]).map { [$0] } ?? []
        if entries.contains(where: { ($0["by"] as? String ?? "").hasPrefix("human:") }) { return "Human-reviewed" }
        return entries.isEmpty ? "Unverified" : "Machine-confirmed"
    }
    var isStale: Bool {
        let value = metadata["stale_after"]
        if let date = value as? Date { return date <= Date() }
        guard let text = value as? String else { return false }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date <= Date() }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: text).map { $0 <= Date() } ?? false
    }

    static func parse(_ raw: String, path: String) -> WikiDocument {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "---" }) else {
            return WikiDocument(relativePath: path, raw: raw, body: raw, metadata: [:], problem: "No YAML frontmatter")
        }
        let body = lines.dropFirst(end + 1).joined(separator: "\n")
        do {
            guard let meta = try Yams.load(yaml: lines[1..<end].joined(separator: "\n")) as? [String: Any] else { throw PiperError("Frontmatter is not a mapping") }
            return WikiDocument(relativePath: path, raw: raw, body: body, metadata: meta, problem: nil)
        } catch { return WikiDocument(relativePath: path, raw: raw, body: body, metadata: [:], problem: error.localizedDescription) }
    }
}

struct WikiScan {
    let documents: [WikiDocument]
    let problems: [String]
}

struct WikiRepository {
    let root: URL
    init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }
    static let destinations = ["sources", "topics", "projects", "decisions"]

    func create() throws {
        let files = FileManager.default
        if files.fileExists(atPath: root.path), !(try files.contentsOfDirectory(atPath: root.path)).filter({ $0 != ".DS_Store" }).isEmpty {
            throw PiperError("Choose an empty folder to create a Wiki. Existing files remain unchanged.")
        }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let index = try containedURL("index.md")
        try Data("---\nokf_version: \"0.2\"\ntitle: Wiki\n---\n\n# Wiki\n".utf8).write(to: index, options: .withoutOverwriting)
    }

    func containedURL(_ path: String, relativeTo document: String? = nil) throws -> URL {
        let base = document.map { root.appendingPathComponent($0).deletingLastPathComponent() } ?? root
        let url = (path.hasPrefix("/") ? root.appendingPathComponent(String(path.dropFirst())) : base.appendingPathComponent(path)).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw PiperError("This link leaves the Wiki folder.") }
        var componentURL = root
        for component in url.path.dropFirst(root.path.count + 1).split(separator: "/") {
            componentURL.appendPathComponent(String(component))
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: componentURL.path)) != nil {
                throw PiperError("Piper does not follow symbolic links inside the Wiki.")
            }
        }
        return url
    }

    func scan(includeIndexes: Bool = false) throws -> WikiScan {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { throw PiperError("The Wiki folder is unavailable. Choose a folder in Settings.") }
        var problems: [String] = []
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { url, error in
            problems.append("\(url.lastPathComponent): \(error.localizedDescription)"); return true
        }) else { throw PiperError("Cannot read the Wiki folder.") }
        var documents: [WikiDocument] = []
        for case let url as URL in files {
            if ["node_modules", "venv", "__pycache__"].contains(url.lastPathComponent) { files.skipDescendants(); continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { files.skipDescendants(); continue }
            let isIndex = ["index.md", "log.md"].contains(url.lastPathComponent)
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md", includeIndexes || !isIndex else { continue }
            let path = String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
            do {
                let raw = try String(contentsOf: url, encoding: .utf8)
                let parsed = WikiDocument.parse(raw, path: path)
                let doc = isIndex && parsed.problem == "No YAML frontmatter"
                    ? WikiDocument(relativePath: path, raw: raw, body: raw, metadata: ["title": url.deletingPathExtension().lastPathComponent == "log" ? "Change Log" : "Overview"], problem: nil)
                    : parsed
                if let problem = doc.problem { problems.append("\(path): \(problem)") }
                documents.append(doc)
            } catch { problems.append("\(path): \(error.localizedDescription)") }
        }
        return WikiScan(documents: documents.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }, problems: problems)
    }

    func validateBundle() throws {
        let index = try String(contentsOf: root.appendingPathComponent("index.md"), encoding: .utf8)
        let doc = WikiDocument.parse(index, path: "index.md")
        guard String(describing: doc.metadata["okf_version"] ?? "") == "0.2" else { throw PiperError("Choose an OKF 0.2 Wiki folder. The root index must declare okf_version: \"0.2\".") }
    }

    func saveBody(_ body: String, of document: WikiDocument) throws -> WikiDocument {
        let prefix = document.frontmatterPrefix
        let separator = prefix.isEmpty || prefix.last?.isNewline == true || body.isEmpty ? "" : "\n"
        let raw = prefix + separator + body
        let data = Data(raw.utf8)
        guard data != Data(document.raw.utf8) else { return document }
        let url = try containedURL(document.id)
        guard try Data(contentsOf: url) == Data(document.raw.utf8) else {
            throw PiperError("This note changed in another editor. Your edits are still open. Copy them before discarding changes and reopening the note.")
        }
        try data.write(to: url, options: .atomic)
        return WikiDocument.parse(raw, path: document.id)
    }

    func export(notes: [Note], title: String, description: String, destination: String, sourceURL: String) throws -> WikiDocument {
        guard !notes.isEmpty, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.destinations.contains(destination) else { throw PiperError("Enter a title and description, and choose a destination.") }
        if !sourceURL.isEmpty {
            guard let url = URL(string: sourceURL), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { throw PiperError("Enter an HTTP or HTTPS source URL.") }
        }
        try validateBundle()
        let lock = try containedURL(".piper-export.lock")
        let descriptor = open(lock.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw PiperError("Another Wiki export is active. If no export is running, remove .piper-export.lock and retry.") }
        defer { close(descriptor); try? FileManager.default.removeItem(at: lock) }
        let scan = try scan()
        guard scan.problems.isEmpty else { throw PiperError("Resolve Wiki read errors before exporting:\n" + scan.problems.joined(separator: "\n")) }
        for doc in scan.documents {
            guard let type = doc.metadata["type"] as? String, !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  doc.metadata["trust_tier"] == nil else { throw PiperError("\(doc.relativePath) has invalid concept metadata. No draft was written.") }
        }
        let ids = Set(notes.map { $0.id.uuidString })
        if let existing = scan.documents.first(where: { $0.captureIDs == ids }) {
            try updateIndexesAndLog(documents: scan.documents, exported: existing)
            return existing
        }
        let folder = try containedURL(destination)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var slug = Self.slug(title)
        let base = slug
        var number = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(slug + ".md").path) { slug = base + "-\(number)"; number += 1 }
        let path = destination + "/" + slug + ".md"
        var meta: [String: Any] = [
            "type": destination == "sources" ? "Source" : "Note",
            "title": title, "description": description, "status": "draft",
            "generated": ["by": "process:piper", "at": ISO8601DateFormatter().string(from: Date())],
            "piper_capture_ids": ids.sorted()
        ]
        let urls = Array(Set(notes.flatMap(\.sourceURLs) + (sourceURL.isEmpty ? [] : [sourceURL]))).sorted()
        if !urls.isEmpty { meta["sources"] = urls.enumerated().map { ["id": "source-\($0.offset + 1)", "resource": $0.element] } }
        meta["captures"] = notes.map { ["id": $0.id.uuidString, "at": ISO8601DateFormatter().string(from: $0.createdAt), "applications": $0.sources] as [String: Any] }
        let yaml = try Yams.dump(object: meta, sortKeys: true)
        let heading = destination == "sources" ? "Captured Excerpts" : "Captured Notes"
        let body = "# \(title.replacingOccurrences(of: "\n", with: " "))\n\n## \(heading)\n\n" + notes.map(\.text).joined(separator: "\n\n---\n\n")
        let references = urls.enumerated().map { "[^source-\($0.offset + 1)]: \($0.element)" }.joined(separator: "\n")
        let raw = "---\n" + yaml + "---\n\n" + body + (references.isEmpty ? "" : "\n\n## Sources\n\n" + urls.indices.map { "[^source-\($0 + 1)]" }.joined(separator: " ") + "\n\n" + references) + "\n"
        let doc = WikiDocument.parse(raw, path: path)
        guard doc.problem == nil else { throw PiperError("Cannot encode the draft metadata.") }
        let url = try containedURL(path)
        try Data(raw.utf8).write(to: url, options: .withoutOverwriting)
        do { try updateIndexesAndLog(documents: scan.documents + [doc], exported: doc) }
        catch { throw PiperError("The draft is saved at \(path), but the index or log update failed. Retry Send to Wiki to repair it.\n\(error.localizedDescription)") }
        return doc
    }

    private func updateIndexesAndLog(documents: [WikiDocument], exported: WikiDocument) throws {
        for doc in documents {
            let url = try containedURL(doc.relativePath)
            guard try String(contentsOf: url, encoding: .utf8) == doc.raw else {
                throw PiperError("A Wiki note changed during export. Retry after the other editor finishes.")
            }
        }
        let groups = Dictionary(grouping: documents, by: \.folder)
        func lines(_ docs: [WikiDocument]) -> String {
            docs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map {
                "* [\(Self.label($0.title))](/\($0.relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0.relativePath)) - \(Self.label($0.description))"
            }.joined(separator: "\n")
        }
        let ordered = groups.keys.sorted { $0.isEmpty ? false : ($1.isEmpty ? true : $0 < $1) }
        let indexBody = ordered.map { folder in
            "# \(folder.isEmpty ? "Bundle" : URL(fileURLWithPath: folder).lastPathComponent.capitalized)\n\n" + lines(groups[folder]!)
        }.joined(separator: "\n\n") + "\n"
        var writes: [(URL, Data, Data?)] = []
        func add(_ path: String, _ value: String) throws {
            let url = try containedURL(path)
            let old = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            writes.append((url, Data(value.utf8), old))
        }
        try add("index.md", "---\nokf_version: \"0.2\"\n---\n\n" + indexBody)
        for folder in ordered where !folder.isEmpty {
            try add(folder + "/index.md", "# \(URL(fileURLWithPath: folder).lastPathComponent.capitalized)\n\n" + lines(groups[folder]!) + "\n")
        }
        let logURL = try containedURL("log.md")
        var log = FileManager.default.fileExists(atPath: logURL.path) ? try String(contentsOf: logURL, encoding: .utf8) : "# Log\n"
        let link = "](/\(exported.relativePath))"
        if !log.contains(link) {
            let day = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
            log += "\n## \(day)\n\n* **Creation**: [\(Self.label(exported.title))](/\(exported.relativePath)) captured with Piper.\n"
            try add("log.md", log)
        }
        for (url, data, old) in writes {
            let current = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            guard current == old else { throw PiperError("\(url.lastPathComponent) changed during export. Retry after the other editor finishes.") }
            if data != old { try data.write(to: url, options: .atomic) }
        }
    }

    static func label(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    static func slug(_ title: String) -> String {
        let value = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? "capture" : String(value.prefix(80))
    }
}
