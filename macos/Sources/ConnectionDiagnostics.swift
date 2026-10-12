import Foundation

enum ConnectionPhase: String, CaseIterable, Identifiable {
    case configuration, deviceKey, ssh, agent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .configuration: return "连接配置格式"
        case .deviceKey: return "本机设备密钥"
        case .ssh: return "SSH 授权与服务器身份"
        case .agent: return "后端健康接口"
        }
    }
}

enum CheckResult: String {
    case waiting = "未检查", running = "检查中", passed = "通过", failed = "失败"
}

struct ConnectionCheck: Identifiable, Equatable {
    let phase: ConnectionPhase
    var result: CheckResult = .waiting
    var detail = ""
    var id: ConnectionPhase { phase }
}

struct ConnectionDiagnostics: Equatable {
    private(set) var checks = ConnectionPhase.allCases.map { ConnectionCheck(phase: $0) }

    mutating func update(_ phase: ConnectionPhase, _ result: CheckResult, detail: String = "") {
        guard let index = checks.firstIndex(where: { $0.phase == phase }) else { return }
        checks[index].result = result
        checks[index].detail = detail
    }

    mutating func fail(_ error: Error) -> String {
        let phase = checks.first(where: { $0.result == .running })?.phase ?? .configuration
        // HTTP bodies, failing URLs and arbitrary NSError descriptions can contain secrets.
        let message: String
        if let ssh = error as? SSHConnectionError {
            message = ssh.localizedDescription // Our own fixed, credential-free messages.
        } else if let hermes = error as? HermlandError, case .http(let status, _) = hermes {
            message = "后端返回 HTTP \(status)。核对后端类型、端口和原服务登录要求。"
        } else if error is CancellationError {
            message = "检查已取消。"
        } else if phase == .deviceKey {
            message = "设备密钥不可用。请检查钥匙串授权，不要复制其他电脑的私钥。"
        } else if phase == .agent {
            message = "后端检查失败。先在常驻 Mac 检查原服务，再核对中转端口；不要改模型或关闭认证。"
        } else {
            message = "配置读取失败。请重新导入管理员提供的 JSON，或核对手动填写项。"
        }
        update(phase, .failed, detail: message)
        return message
    }

    func report(backend: AgentBackend, version: String) -> String {
        let lines = checks.map { "\($0.phase.title)：\($0.result.rawValue)\($0.detail.isEmpty ? "" : " — " + $0.detail)" }
        return (["Hermland \(version) · \(backend.title)"] + lines
                + ["网页登录与模型回答：未由本检查验证。", "此报告不含连接地址、密钥、令牌或会话内容。"])
            .joined(separator: "\n")
    }
}
