import Foundation

struct GatewayStatus: Equatable {
    var version: String
    var model: String
    var provider: String
    var gatewayRunning: Bool
    var activeSessions: Int
    var authRequired: Bool
    var authProviders: [String]

    var summary: String {
        let gate = gatewayRunning ? "消息网关在跑" : "消息网关未开"
        return "Hermes \(version) · \(model) · \(gate)"
    }
}

struct ChatSession: Identifiable, Hashable {
    var id: String
    var title: String
    var preview: String
    var lastActive: Date?
    var model: String
    var isActive: Bool
}

struct ChatMessage: Identifiable, Hashable {
    enum Role: String {
        case user
        case assistant
        case system
        case tool
        case unknown
    }

    var id: String
    var role: Role
    var text: String
    var isStreaming: Bool
}

struct ConnectionSettings: Equatable {
    var host: String
    var port: Int
    var username: String
    var password: String
    static let `default` = ConnectionSettings(
        host: "127.0.0.1",
        port: 19121,
        username: "",
        password: ""
    )

    var baseURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if port != 80 {
            components.port = port
        }
        return components.url
    }

    var displayURL: String {
        if port == 80 {
            return "http://\(host)"
        }
        return "http://\(host):\(port)"
    }
}

enum HermlandError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case unauthorized
    case decode
    case disconnected
    case rpc(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "地址无效"
        case .http(let code, let body):
            return "服务器返回 \(code)：\(body)"
        case .unauthorized:
            return "Hermes 后端要求登录，请检查后端认证配置"
        case .decode:
            return "服务器返回的数据读不出来"
        case .disconnected:
            return "和 Mini 的连接断了"
        case .rpc(let message):
            return message
        }
    }
}

enum JSONValue {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(_ value: Any?) {
        switch value {
        case let dict as [String: Any]:
            self = .object(dict.mapValues { JSONValue($0) })
        case let list as [Any]:
            self = .array(list.map { JSONValue($0) })
        case let text as String:
            self = .string(text)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        default:
            self = .null
        }
    }

    subscript(_ key: String) -> JSONValue? {
        if case .object(let object) = self {
            return object[key]
        }
        return nil
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var int: Int? {
        if case .number(let value) = self { return Int(value) }
        if case .string(let value) = self { return Int(value) }
        return nil
    }

    var double: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var textContent: String {
        switch self {
        case .string(let value):
            return value
        case .array(let items):
            return items.compactMap { item in
                if let text = item.string { return text }
                if let text = item["text"]?.string { return text }
                if let text = item["content"]?.string { return text }
                return nil
            }.joined()
        case .object(let object):
            if let text = object["text"]?.string { return text }
            if let text = object["content"]?.textContent { return text }
            return ""
        default:
            return ""
        }
    }
}

enum SessionParser {
    static func sessions(from value: JSONValue) -> [ChatSession] {
        let rows = value["sessions"]?.array ?? value.array ?? []
        return rows.compactMap(session(from:))
    }

    static func session(from value: JSONValue) -> ChatSession? {
        let id = value["id"]?.string ?? value["session_id"]?.string
        guard let id, !id.isEmpty else { return nil }
        let title = value["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preview = value["preview"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = value["model"]?.string ?? value["model_name"]?.string ?? ""
        return ChatSession(
            id: id,
            title: title.isEmpty ? (preview.isEmpty ? "未命名会话" : preview) : title,
            preview: preview,
            lastActive: date(from: value["last_active"] ?? value["updated_at"] ?? value["started_at"]),
            model: model,
            isActive: value["is_active"]?.bool ?? false
        )
    }

    static func messages(from value: JSONValue) -> [ChatMessage] {
        let rows = value["messages"]?.array ?? value.array ?? []
        return rows.compactMap(message(from:))
    }

    static func message(from value: JSONValue) -> ChatMessage? {
        let text = (value["content"] ?? value["text"])?.textContent
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let roleRaw = value["role"]?.string ?? "unknown"
        let role = ChatMessage.Role(rawValue: roleRaw) ?? .unknown
        if text.isEmpty && role == .tool { return nil }
        let id = value["id"]?.string
            ?? value["message_id"]?.string
            ?? UUID().uuidString
        return ChatMessage(id: id, role: role, text: text, isStreaming: false)
    }

    static func status(from value: JSONValue) -> GatewayStatus {
        let model = value["model"]?.string
            ?? value["default_model"]?.string
            ?? value["config"]?["model"]?.string
            ?? "—"
        let provider = value["provider"]?.string
            ?? value["model_provider"]?.string
            ?? ""
        let providers = value["auth_providers"]?.array?.compactMap(\.string)
            ?? value["providers"]?.array?.compactMap { $0["name"]?.string ?? $0.string }
            ?? []
        return GatewayStatus(
            version: value["version"]?.string ?? value["hermes_version"]?.string ?? "—",
            model: model,
            provider: provider,
            gatewayRunning: value["gateway_running"]?.bool ?? false,
            activeSessions: value["active_sessions"]?.int ?? 0,
            authRequired: value["auth_required"]?.bool ?? false,
            authProviders: providers
        )
    }

    static func statusFromWebUI(health: JSONValue, settings: JSONValue) -> GatewayStatus {
        return GatewayStatus(
            version: settings["webui_version"]?.string ?? "webui",
            model: settings["default_model"]?.string ?? "—",
            provider: settings["default_model_provider"]?.string ?? "",
            gatewayRunning: health["status"]?.string == "ok",
            activeSessions: health["sessions"]?.int ?? 0,
            authRequired: settings["auth_enabled"]?.bool ?? false,
            authProviders: []
        )
    }

    private static func date(from value: JSONValue?) -> Date? {
        guard let value else { return nil }
        if let seconds = value.double, seconds > 1_000_000_000 {
            return Date(timeIntervalSince1970: seconds)
        }
        if let text = value.string {
            if let seconds = Double(text), seconds > 1_000_000_000 {
                return Date(timeIntervalSince1970: seconds)
            }
            return ISO8601DateFormatter().date(from: text)
        }
        return nil
    }
}
