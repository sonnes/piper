import Foundation

/// The allow rule that Always writes for a tool call, in the syntax of Claude
/// Code settings.
public enum PermissionRule {

    /// The settings file for rules of one reader. Claude Code reads it with the
    /// shared `.claude/settings.json`.
    public static let settingsPath = ".claude/settings.local.json"

    /// The rule that allows calls like this one: the tool name, `Tool(program:*)`
    /// for a command, or `Tool(domain:example.com)` for a web page. A question
    /// and a mode change have no rule.
    public static func rule(for request: PermissionRequest) -> String? {
        let tool = request.toolName
        guard !request.isQuestion else { return nil }
        switch request.kind {
        case .switchMode:
            return nil
        case .execute:
            let command = request.input["command"]?.string?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let program = command.split(whereSeparator: \.isWhitespace).first else { return tool }
            return "\(tool)(\(program):*)"
        case .fetch:
            guard let host = request.input["url"]?.string.flatMap({ URL(string: $0)?.host }) else { return tool }
            return "\(tool)(domain:\(host))"
        default:
            return tool
        }
    }

    /// Adds a rule to `permissions.allow` in the settings file of a folder.
    /// The file keeps its other keys. A rule that is already there is not added
    /// again. A file that exists and cannot be read throws, and stays as it is.
    public static func append(_ rule: String, to folder: URL) throws {
        let url = folder.appendingPathComponent(settingsPath)
        var settings: [String: Any] = [:]
        let stored = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : Data()
        if !stored.isEmpty {
            guard let object = try JSONSerialization.jsonObject(with: stored) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
            }
            settings = object
        }
        var permissions = settings["permissions"] as? [String: Any] ?? [:]
        var allow = permissions["allow"] as? [String] ?? []
        guard !allow.contains(rule) else { return }
        allow.append(rule)
        permissions["allow"] = allow
        settings["permissions"] = permissions
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
