import Foundation

/// One JSON-RPC 2.0 message on one line, the framing of ACP over stdio.
public enum JSONRPCMessage: Equatable, Sendable {
    case request(id: JSONValue, method: String, params: JSONValue)
    case notification(method: String, params: JSONValue)
    case response(id: JSONValue, result: JSONValue)
    case error(id: JSONValue, code: Int, message: String)

    /// The code for a method that Piper does not offer.
    public static let methodNotFound = -32601
    /// The code for a request whose parameters Piper cannot read.
    public static let invalidParams = -32602

    // MARK: - Reading

    /// Reads one line. A line that is not a JSON-RPC message returns nil.
    public static func parse(_ line: String) -> JSONRPCMessage? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let json = JSONValue(object)
        let id = json["id"]
        if let method = json["method"]?.string {
            let params = json["params"] ?? .null
            if let id, id != .null { return .request(id: id, method: method, params: params) }
            return .notification(method: method, params: params)
        }
        guard let id else { return nil }
        if let error = json["error"] {
            return .error(id: id, code: error["code"]?.int ?? 0, message: error["message"]?.string ?? "Unknown error")
        }
        return .response(id: id, result: json["result"] ?? .null)
    }

    // MARK: - Writing

    /// The message as one line of JSON, with no line break inside.
    public var line: String {
        var object: [String: JSONValue] = ["jsonrpc": .string("2.0")]
        switch self {
        case .request(let id, let method, let params):
            object["id"] = id
            object["method"] = .string(method)
            object["params"] = params
        case .notification(let method, let params):
            object["method"] = .string(method)
            object["params"] = params
        case .response(let id, let result):
            object["id"] = id
            object["result"] = result
        case .error(let id, let code, let message):
            object["id"] = id
            object["error"] = .object(["code": .number(Double(code)), "message": .string(message)])
        }
        let data = (try? JSONSerialization.data(withJSONObject: JSONValue.object(object).any,
                                                options: [.withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
