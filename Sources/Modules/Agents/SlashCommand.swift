import Foundation

/// Text of the form `/name arguments`.
public struct SlashCommand: Codable, Equatable, Sendable {

    // MARK: - Properties

    public let name: String
    public let arguments: String

    /// The prompt that `claude -p` receives.
    public var prompt: String { arguments.isEmpty ? "/" + name : "/\(name) \(arguments)" }

    // MARK: - Initialization

    public init(name: String, arguments: String = "") {
        self.name = name
        self.arguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads a command from the start of `text`. Returns nil when the text does
    /// not start with a slash and a name.
    public init?(_ text: String) {
        guard text.hasPrefix("/") else { return nil }
        let body = text.dropFirst()
        let name = body.prefix { !$0.isWhitespace }
        guard Self.isName(name) else { return nil }
        self.init(name: String(name), arguments: String(body.dropFirst(name.count)))
    }

    // MARK: - Names

    /// The name that the reader is typing, while the text holds only a slash
    /// and part of a name. An empty string means the reader typed only the slash.
    public static func partialName(_ text: String) -> String? {
        guard text.hasPrefix("/") else { return nil }
        let name = text.dropFirst()
        guard name.isEmpty || isName(name) else { return nil }
        return String(name)
    }

    /// True for a skill name: letters, digits, `-`, `_`, and `:`.
    public static func isName<S: StringProtocol>(_ name: S) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == ":"
        }
    }
}
