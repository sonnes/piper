import Foundation

/// Turns the text of the search field into ranked suggestions.
///
/// The parser holds no user interface code and reads no files. The caller
/// supplies the commands, the skills, the actions, and the file candidates.
/// One parser serves the home list and the toolbar popover.
public struct CommandParser {
    public let commands: [WikiCommand]
    public let skills: [WikiSkill]
    public let actions: [CommandAction]

    // MARK: - Life Cycle

    public init(commands: [WikiCommand] = [], skills: [WikiSkill] = [], actions: [CommandAction] = []) {
        self.commands = commands
        self.skills = skills
        self.actions = actions
    }

    // MARK: - Functions

    /// Returns the rows for `text`, in rank order.
    ///
    /// The first character selects the source:
    ///
    /// - `/` gives commands, then skills.
    /// - `>` gives the injected actions.
    /// - Anything else gives file names, file text, commands, skills, then actions.
    ///
    /// Empty text gives no rows. Text that matches nothing gives one fallback row.
    public func suggestions(for text: String, files: [FileCandidate] = []) -> [CommandSuggestion] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        if query.hasPrefix("/") { return extensionRows(query) }
        if query.hasPrefix(">") { return actionRows(query) }
        return searchRows(query, files: files)
    }
}

// MARK: - Sources

private extension CommandParser {
    /// The rows for text that starts with `/`: commands first, then skills.
    ///
    /// The name ends at the first space. The rest of the line is the arguments.
    func extensionRows(_ query: String) -> [CommandSuggestion] {
        let rest = query.dropFirst()
        let name = String(rest.prefix { !$0.isWhitespace })
        let arguments = String(rest.dropFirst(name.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        var rows = commands.filter { contains($0.name, name) }.map { commandRow($0, arguments: arguments) }
        rows += skills.filter { contains($0.name, name) }.map { skillRow($0, arguments: arguments) }
        return rows.isEmpty ? [fallbackRow(query)] : rows
    }

    /// The rows for text that starts with `>`: the injected actions, and nothing else.
    func actionRows(_ query: String) -> [CommandSuggestion] {
        let name = String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = actions.filter { contains($0.title, name) }.map(actionRow)
        return rows.isEmpty ? [fallbackRow(query)] : rows
    }

    /// The rows for free text, in rank order.
    ///
    /// A file that matches by name does not appear again in the text group.
    func searchRows(_ query: String, files: [FileCandidate]) -> [CommandSuggestion] {
        let nameHits = files.filter { contains($0.name, query) }
        let matched = Set(nameHits.map(\.id))
        let textHits = files.filter { !matched.contains($0.id) && contains($0.excerpt, query) }

        var rows = nameHits.map(fileRow)
        rows += textHits.map(fileTextRow)
        rows += commands.filter { contains($0.name + " " + $0.summary, query) }
            .map { commandRow($0, arguments: "") }
        rows += skills.filter { contains($0.name + " " + $0.summary, query) }
            .map { skillRow($0, arguments: "") }
        rows += actions.filter { contains($0.title, query) }.map(actionRow)
        return rows.isEmpty ? [fallbackRow(query)] : rows
    }
}

// MARK: - Rows

private extension CommandParser {
    func commandRow(_ command: WikiCommand, arguments: String) -> CommandSuggestion {
        let title = command.takesArguments ? "/\(command.name) \(command.argumentHint)" : "/\(command.name)"
        return CommandSuggestion(
            id: "command:" + command.name,
            title: title,
            detail: command.summary,
            kind: .command,
            scope: command.scope,
            target: .command(command, arguments: arguments)
        )
    }

    func skillRow(_ skill: WikiSkill, arguments: String) -> CommandSuggestion {
        CommandSuggestion(
            id: "skill:" + skill.name,
            title: "/" + skill.name,
            detail: skill.summary,
            kind: .skill,
            scope: skill.scope,
            target: .skill(skill, arguments: arguments)
        )
    }

    func fileRow(_ file: FileCandidate) -> CommandSuggestion {
        CommandSuggestion(
            id: "file:" + file.url.path,
            title: file.name,
            detail: file.path,
            kind: .file,
            target: .file(file)
        )
    }

    func fileTextRow(_ file: FileCandidate) -> CommandSuggestion {
        CommandSuggestion(
            id: "fileText:" + file.url.path,
            title: file.name,
            detail: file.excerpt,
            kind: .fileText,
            target: .file(file)
        )
    }

    func actionRow(_ action: CommandAction) -> CommandSuggestion {
        CommandSuggestion(
            id: "action:" + action.title,
            title: action.title,
            detail: action.detail,
            kind: .action,
            target: .action(action)
        )
    }

    func fallbackRow(_ query: String) -> CommandSuggestion {
        CommandSuggestion(
            id: "fallback",
            title: "Search every file for “\(query)”",
            detail: "Nothing else matches this text.",
            kind: .fallback,
            target: .searchEverything(query)
        )
    }
}

// MARK: - Matching

private extension CommandParser {
    /// Reports whether `haystack` holds `needle`, ignoring case.
    ///
    /// An empty needle matches everything, so `/` alone lists every command.
    func contains(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        return haystack.range(of: needle, options: .caseInsensitive) != nil
    }
}
