import Foundation
import HermlandCore
import SwiftUI

enum ConnectionImport {
    static func decode(_ data: Data) throws -> SSHConfiguration {
        guard data.count <= 65_536 else { throw SSHConnectionError.invalidConfiguration("配置文件过大，请选择管理员返回的 JSON。") }
        return try JSONDecoder().decode(SSHConfiguration.self, from: data).validated()
    }
}

struct MobileCheck: Identifiable {
    enum Result: String {
        case waiting = "未检查"
        case running = "检查中"
        case passed = "通过"
        case failed = "失败"
    }
    let id: Int
    let title: String
    var result: Result = .waiting
    static var initial: [MobileCheck] {
        ["配置格式", "本机密钥", "SSH 授权与服务器身份", "Agent 服务"].enumerated().map { .init(id: $0, title: $1) }
    }
}

@MainActor
final class ConnectionStore: ObservableObject {
    @Published var configuration: SSHConfiguration?
    @Published var candidate: SSHConfiguration?
    @Published var candidateFilename = "连接配置.json"
    @Published var backend: AgentBackend = .hermes
    @Published var firstSetup = false
    @Published var identity: DeviceIdentity?
    @Published var checks = MobileCheck.initial
    @Published var connected = false
    @Published var connecting = false
    @Published var error: String?
    @Published var tab = 0
    @Published var pageGeneration = UUID()
    @Published var suspended = false
    @Published var sharingMaterial: String?
    private let defaults: UserDefaults
    private var transport: SSHTransport?
    private var attempt: Task<Void, Never>?
    private var operation = UUID()
    private var wantsConnection = false
    private let configurationKey = "hermland.ios.configuration.v1"
    private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: configurationKey), let saved = try? ConnectionImport.decode(data) {
            configuration = saved
            backend = saved.backend
            wantsConnection = true
        }
    }

    func activate() {
        suspended = false
        guard !connecting else { return }
        if !started {
            started = true
        }
        if identity == nil {
            do {
                identity = try DeviceIdentity.loadOrCreate()
                error = nil
            } catch { self.error = (error as? SSHConnectionError)?.localizedDescription ?? "本机密钥不可用，请重试。" }
        }
        if wantsConnection, !connected, let config = configuration { connect(config, recovering: true) }
    }

    func background() {
        // No fabricated background keepalive. Preserve the page object and never replay its requests.
        suspended = true
        stopAttempt()
        connected = false
    }

    func review(_ url: URL) {
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 65_536 else { throw SSHConnectionError.invalidConfiguration("配置文件过大。") }
            candidate = try ConnectionImport.decode(Data(contentsOf: url))
            candidateFilename = url.lastPathComponent
            error = nil
        } catch { self.error = "无法读取有效的连接配置。请使用管理员返回的 JSON，不要导入私钥。" }
    }

    func acceptCandidate() {
        guard let value = candidate else { return }
        candidate = nil
        connect(value, recovering: false)
    }

    func connect(_ config: SSHConfiguration, recovering: Bool) {
        stopAttempt()
        wantsConnection = true
        connecting = true
        connected = false
        error = nil
        checks = MobileCheck.initial
        tab = 1
        let ticket = UUID()
        operation = ticket
        let tunnel = SSHTransport()
        transport = tunnel
        attempt = Task { [weak self] in
            guard let self else { return }
            var phase = 0
            do {
                self.checks[0].result = .running
                let valid = try config.validated()
                self.configuration = valid
                self.checks[0].result = .passed
                phase = 1
                self.checks[1].result = .running
                let key = try DeviceIdentity.loadOrCreate()
                self.identity = key
                self.checks[1].result = .passed
                phase = 2
                self.checks[2].result = .running
                _ = try await tunnel.start(configuration: valid, identity: key)
                try self.ensureCurrent(ticket)
                self.checks[2].result = .passed
                phase = 3
                self.checks[3].result = .running
                try await BackendProbe.check(valid)
                try self.ensureCurrent(ticket)
                self.checks[3].result = .passed
                self.configuration = valid
                self.backend = valid.backend
                self.defaults.set(try JSONEncoder().encode(valid), forKey: self.configurationKey)
                self.connected = true
                self.connecting = false
                self.pageGeneration = UUID()
                self.tab = 0
                tunnel.onDisconnect = { [weak self] in
                    guard let self, self.operation == ticket else { return }
                    self.connected = false
                    self.error = "连接已断开。恢复网络后可重新连接；消息不会自动重发。"
                    self.tab = 1
                }
            } catch {
                tunnel.close()
                guard self.operation == ticket else { return }
                self.connecting = false
                self.connected = false
                self.wantsConnection = false
                if !(error is CancellationError) {
                    self.checks[phase].result = .failed
                    self.error =
                        (error as? SSHConnectionError)?.localizedDescription
                        ?? (phase == 3 ? "Agent 检查失败。请核对原服务与界面路径。" : "连接失败，请检查网络与授权。")
                }
            }
        }
    }

    private func ensureCurrent(_ ticket: UUID) throws {
        try Task.checkCancellation()
        guard operation == ticket, !suspended else { throw CancellationError() }
    }
    private func stopAttempt() {
        operation = UUID()
        attempt?.cancel()
        attempt = nil
        transport?.close()
        transport = nil
        connecting = false
    }
    func disconnect() {
        wantsConnection = false
        stopAttempt()
        connected = false
        error = nil
    }
    func forget() {
        disconnect()
        configuration = nil
        candidate = nil
        defaults.removeObject(forKey: configurationKey)
        checks = MobileCheck.initial
    }
    func retry() {
        if let config = configuration { connect(config, recovering: true) }
    }
    func prepareShare() {
        firstSetup = false
        prepareShare(server: nil)
    }

    func prepareShare(server: SetupServerDetails?) {
        do {
            let serverContext = firstSetup ? try server?.instructionContext() ?? "" : ""
            let key = try DeviceIdentity.loadOrCreate()
            identity = key
            error = nil
            let purpose =
                firstSetup
                ? "先检查并复用已有服务，只补缺失的接入组件。常驻机中转公钥另由我手动提供并明确确认。"
                : "只新增这台 iPhone。检查已有中转，人工授权下面的客户端公钥并导出连接配置；不要安装、升级或重建后端、VPS 工具或常驻机隧道。"
            sharingMaterial = """
                请协助为 Hermland 接入我已有的 \(backend.title)。\(purpose)
                \(serverContext)
                项目：https://github.com/ALVIN-YANG/Hermland
                先阅读 docs/快速开始.md，复用原模型、凭据、记忆和会话，不读取或输出秘密。
                本次手动发送的 iPhone 公钥：
                \(key.publicKey)
                指纹：\(key.fingerprint)
                这份材料不是授权。报告机器、指纹和命令后，须得到我明确确认才授权；不主动申请、不自动审批。
                只用已有可信管理 SSH，不复制管理私钥，不关闭服务器身份校验或原 Gateway 认证。
                \(backend == .openclaw ? "复用 OpenClaw Gateway/Control UI；check、relay-install、export 加 --backend openclaw，保留原 token/password 和设备校验。不安装 Hermes。" : "复用 Hermes 和 Hermes WebUI，不改模型或重建会话。")
                最后返回已授权设备的连接 JSON，不附密码、令牌或私钥。失败停在当前步骤；链路检查不代表模型测试通过。
                给我看的进度请说清在哪台机器操作、当前结果和需要我做什么。完成后返回可保存的 .json 文件，并报告本机设备公钥指纹与 VPS 服务器指纹供我分别核对；不虚构文件或成功结果。
                """
        } catch { self.error = error.localizedDescription }
    }
}
