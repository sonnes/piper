import Foundation

/// The allow rule that Always writes for a tool call, in the syntax of Claude
/// Code settings.
public enum PermissionRule {

    /// The settings file for rules of one reader. Claude Code reads it with the
    /// shared `.claude/settings.json`.
    public static let settingsPath = ".claude/settings.local.json"

    /// The rule that allows calls like this one: `Edit`, `Bash(python3:*)`, or
    /// `WebFetch(domain:example.com)`. A question has no rule.
    public static func rule(toolName: String, input: JSONValue) -> String? {
        switch toolName {
        case "AskUserQuestion", "ExitPlanMode":
            return nil
        case "Bash":
            let command = input["command"]?.string?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let program = command.split(whereSeparator: \.isWhitespace).first else { return "Bash" }
            return "Bash(\(program):*)"
        case "WebFetch":
            guard let host = input["url"]?.string.flatMap({ URL(string: $0)?.host }) else { return "WebFetch" }
            return "WebFetch(domain:\(host))"
        default:
            return toolName
        }
    }

    /// Adds a rule to `permissions.allow` in the settings file of a folder.
    /// The file keeps its other keys. A rule that is already there is not added again.
    public static func append(_ rule: String, to folder: URL) throws {
        let url = folder.appendingPathComponent(settingsPath)
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
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
