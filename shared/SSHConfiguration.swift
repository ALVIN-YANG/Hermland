import Foundation
import CryptoKit

public struct SSHConfiguration: Codable, Equatable, Sendable {
    public var host = ""
    public var port = 22
    public var user = ""
    public var remotePort = 19119
    public var localPort = 19121
    /// Obtained from an administrator over an already trusted channel.
    public var serverPublicKey = ""
    public var backend: AgentBackend = .hermes
    public var controlUIPath = "/"

    enum CodingKeys: String, CodingKey {
        case host, port, user, remotePort, localPort, serverPublicKey, backend, controlUIPath
    }

    public init(host: String = "", port: Int = 22, user: String = "", remotePort: Int = 19119,
         localPort: Int = 19121, serverPublicKey: String = "", backend: AgentBackend = .hermes,
         controlUIPath: String = "/") {
        self.host = host
        self.port = port
        self.user = user
        self.remotePort = remotePort
        self.localPort = localPort
        self.serverPublicKey = serverPublicKey
        self.backend = backend
        self.controlUIPath = controlUIPath
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        host = try values.decode(String.self, forKey: .host)
        port = try values.decode(Int.self, forKey: .port)
        user = try values.decode(String.self, forKey: .user)
        remotePort = try values.decode(Int.self, forKey: .remotePort)
        localPort = try values.decode(Int.self, forKey: .localPort)
        serverPublicKey = try values.decode(String.self, forKey: .serverPublicKey)
        // Existing configurations remain Hermes; unknown backend values still fail closed.
        backend = try values.decodeIfPresent(AgentBackend.self, forKey: .backend) ?? .hermes
        controlUIPath = try values.decodeIfPresent(String.self, forKey: .controlUIPath) ?? "/"
    }

    public var displayAddress: String { "\(user)@\(host):\(port)" }
    public var localURL: URL {
        var value = URLComponents(string: "http://127.0.0.1:\(localPort)")!
        value.path = controlUIPath
        return value.url!
    }

    /// A loopback URL can point to another server later. Never share its browser credentials.
    public var websiteDataStoreID: UUID {
        let route = [host.lowercased(), String(port), user, String(remotePort), String(localPort),
                     serverPublicKey, backend.rawValue, controlUIPath]
        let data = try! JSONEncoder().encode(route)
        let bytes = Array(SHA256.hash(data: data).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    public func validated() throws -> SSHConfiguration {
        var value = self
        value.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        value.user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.host.range(of: #"\A[A-Za-z0-9][A-Za-z0-9.-]*\z"#, options: .regularExpression) != nil,
              value.user.range(of: #"\A[a-z_][a-z0-9_-]{0,31}\z"#, options: .regularExpression) != nil,
              value.user != "root" else {
            throw SSHConnectionError.invalidConfiguration("填写服务器 IP／域名和专用 SSH 用户，不能使用 root")
        }
        guard [port, remotePort, localPort].allSatisfy({ (1...65535).contains($0) }) else {
            throw SSHConnectionError.invalidConfiguration("端口必须在 1–65535 之间")
        }
        value.serverPublicKey = try Self.normalizedPublicKey(serverPublicKey)
        value.controlUIPath = try AgentBackend.normalizedUIPath(controlUIPath)
        guard backend == .openclaw || value.controlUIPath == "/" else {
            throw SSHConnectionError.invalidConfiguration("Hermes WebUI 使用根路径 /；自定义界面路径仅用于 OpenClaw")
        }
        return value
    }

    public static func normalizedPublicKey(_ text: String) throws -> String {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", omittingEmptySubsequences: true)
        guard !text.contains("\n"), !text.contains("\r"), parts.count >= 2,
              parts[0] == "ssh-ed25519", let data = Data(base64Encoded: String(parts[1])),
              data.count == 51,
              Array(data.prefix(4)) == [0, 0, 0, 11],
              String(data: data.subdata(in: 4..<15), encoding: .utf8) == "ssh-ed25519",
              Array(data[15..<19]) == [0, 0, 0, 32] else {
            throw SSHConnectionError.invalidConfiguration("需要管理员提供的完整 Ed25519 服务器公钥，不能只填指纹")
        }
        return "ssh-ed25519 \(parts[1])"
    }

    public static func fingerprint(_ publicKey: String) -> String? {
        guard let normalized = try? normalizedPublicKey(publicKey),
              let data = Data(base64Encoded: String(normalized.split(separator: " ")[1])) else { return nil }
        return "SHA256:" + Data(SHA256.hash(data: data)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    public var knownHostsEntry: String {
        let name = port == 22 ? host : "[\(host)]:\(port)"
        return "\(name) \(serverPublicKey)\n"
    }

    public func sshArguments(identity: URL, knownHosts: URL) -> [String] {
        ["-F", "/dev/null", "-N", "-T", "-v", "-p", String(port),
         "-i", identity.path,
         "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=none",
         "-o", "StrictHostKeyChecking=yes", "-o", "UpdateHostKeys=no",
         "-o", "UserKnownHostsFile=\(knownHosts.path)", "-o", "GlobalKnownHostsFile=/dev/null",
         "-o", "ControlMaster=no", "-o", "ControlPath=none",
         "-o", "ExitOnForwardFailure=yes", "-o", "ConnectTimeout=8",
         "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=2",
         "-L", "127.0.0.1:\(localPort):127.0.0.1:\(remotePort)", "\(user)@\(host)"]
    }
}

public enum SSHConnectionError: LocalizedError {
    case invalidConfiguration(String)
    case keychain(Int32)
    case process(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message), .process(let message): return message
        case .keychain(let code): return "无法读取或保存设备密钥，钥匙串错误：\(code)"
        }
    }
}
