import Foundation

/// Both backends use their own web UI. SSH transport and device authorization are shared.
public enum AgentBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case hermes
    case openclaw

    public var id: String { rawValue }
    public var title: String { self == .hermes ? "Hermes" : "OpenClaw" }
    public var healthPath: String { self == .hermes ? "/health" : "/healthz" }

    public static func normalizedUIPath(_ text: String) throws -> String {
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if path == "/" { return path }
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              path.range(of: #"\A/[A-Za-z0-9._~/-]+\z"#, options: .regularExpression) != nil,
              path.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }),
              !path.contains("//") else {
            throw SSHConnectionError.invalidConfiguration("界面路径应为 / 或 /openclaw，不要填写完整地址、令牌或查询参数")
        }
        return path.hasSuffix("/") ? path : path + "/"
    }
}
