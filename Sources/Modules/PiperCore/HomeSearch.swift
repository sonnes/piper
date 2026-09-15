import Foundation

/// Ranks file matches and local app actions for Home search.
public struct HomeSearch {
    public let actions: [HomeAction]

    // MARK: - Life Cycle

    public init(actions: [HomeAction] = []) {
        self.actions = actions
    }

    // MARK: - Functions

    /// Returns matching rows, or a search fallback when no item matches.
    public func suggestions(for text: String, files: [FileCandidate] = []) -> [HomeSuggestion] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        if query.hasPrefix(">") { return actionRows(query) }
        return searchRows(query, files: files)
    }
}

// MARK: - Sources

private extension HomeSearch {
    /// The rows for text that starts with `>`: the injected actions, and nothing else.
    func actionRows(_ query: String) -> [HomeSuggestion] {
        let name = String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = actions.filter { contains($0.title, name) }.map(actionRow)
        return rows.isEmpty ? [fallbackRow(query)] : rows
    }

    /// The rows for free text, in rank order.
    ///
    /// A file that matches by name does not appear again in the text group.
    func searchRows(_ query: String, files: [FileCandidate]) -> [HomeSuggestion] {
        let nameHits = files.filter { contains($0.name, query) }
        let matched = Set(nameHits.map(\.id))
        let textHits = files.filter { !matched.contains($0.id) && contains($0.excerpt, query) }

        var rows = nameHits.map(fileRow)
        rows += textHits.map(fileTextRow)
        rows += actions.filter { contains($0.title, query) }.map(actionRow)
        return rows.isEmpty ? [fallbackRow(query)] : rows
    }
}

// MARK: - Rows

private extension HomeSearch {
    func fileRow(_ file: FileCandidate) -> HomeSuggestion {
        HomeSuggestion(
            id: "file:" + file.url.path,
            title: file.name,
            detail: file.path,
            kind: .file,
            target: .file(file)
        )
    }

    func fileTextRow(_ file: FileCandidate) -> HomeSuggestion {
        HomeSuggestion(
            id: "fileText:" + file.url.path,
            title: file.name,
            detail: file.excerpt,
            kind: .fileText,
            target: .file(file)
        )
    }

    func actionRow(_ action: HomeAction) -> HomeSuggestion {
        HomeSuggestion(
            id: "action:" + action.title,
            title: action.title,
            detail: action.detail,
            kind: .action,
            target: .action(action)
        )
    }

    func fallbackRow(_ query: String) -> HomeSuggestion {
        HomeSuggestion(
            id: "fallback",
            title: "Search every file for “\(query)”",
            detail: "Nothing else matches this text.",
            kind: .fallback,
            target: .searchEverything(query)
        )
    }
}

// MARK: - Matching

private extension HomeSearch {
    /// Reports whether `haystack` holds `needle`, ignoring case.
    ///
    /// An empty needle matches every local action.
    func contains(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        return haystack.range(of: needle, options: .caseInsensitive) != nil
    }
}
