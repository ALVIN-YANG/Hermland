import AppKit
import Foundation
import SwiftUI

enum AppStateEventBus {
    static var handler: ((String, String, JSONValue) -> Void)?

    static func forward(type: String, sessionID: String, payload: JSONValue) {
        handler?(type, sessionID, payload)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var settings: ConnectionSettings
    @Published var isConnecting = false
    @Published var isConnected = false
    @Published var isSending = false
    @Published var status: GatewayStatus?
    @Published var signedInAs = ""
    @Published var sessions: [ChatSession] = []
    @Published var selectedSessionID: String?
    @Published var messages: [ChatMessage] = []
    /// Gateway in-memory id for the open chat. REST list ids are stored ids.
    private var liveSessionID: String?
    @Published var draft = ""
    @Published var banner: String?
    @Published var dashboardURL: URL?
    @Published var sshConfiguration: SSHConfiguration {
        didSet {
            if !isConnecting && !isConnected { diagnostics = ConnectionDiagnostics() }
        }
    }
    @Published var devicePublicKey = ""
    @Published var diagnostics = ConnectionDiagnostics()

    private var client: HermesClient?
    private let tunnel = SSHTunnel()
    private var deviceIdentity: SSHIdentity?
    private var identityTask: Task<SSHIdentity, Error>?
    private var identityError: Error?
    private var reconnectTask: Task<Void, Never>?
    private var wantsConnection = false
    private var startupAttempted = false
    private let sshSettingsKey = "hermland.ssh.configuration.v1"
    private var refreshTask: Task<Void, Never>?
    init() {
        self.settings = .default
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: sshSettingsKey),
           let saved = try? JSONDecoder().decode(SSHConfiguration.self, from: data) {
            sshConfiguration = saved
        } else {
            sshConfiguration = SSHConfiguration()
        }
        tunnel.onUnexpectedExit = { [weak self] in self?.reconnectAfterTunnelExit() }
    }

    func connectIfConfigured() async {
        guard !startupAttempted else { return }
        startupAttempted = true
        await prepareDeviceIdentity()
        if (try? sshConfiguration.validated()) != nil { await connect() }
    }

    func prepareDeviceIdentity() async {
        guard deviceIdentity == nil else { return }
        let pending = identityTask ?? Task.detached(priority: .userInitiated) {
            let identity = try SSHIdentity.loadOrCreate()
            try identity.publishPublicKey()
            return identity
        }
        identityTask = pending
        defer { identityTask = nil }
        do {
            let identity = try await pending.value
            deviceIdentity = identity
            devicePublicKey = identity.publicKey
            identityError = nil
        } catch {
            identityError = error
            banner = error.localizedDescription
        }
    }

    func copyDevicePublicKey() async {
        await prepareDeviceIdentity()
        guard !devicePublicKey.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(devicePublicKey, forType: .string)
    }

    /// Read and validate without replacing the trusted route or starting a connection.
    func readSSHConfiguration(from url: URL) throws -> SSHConfiguration {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try JSONDecoder().decode(SSHConfiguration.self, from: Data(contentsOf: url)).validated()
    }

    func connect() async {
        guard !isConnecting else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        wantsConnection = true
        banner = nil
        isConnecting = true
        diagnostics = ConnectionDiagnostics()
        defer { isConnecting = false }
        do {
            try await establishSSHConnection()
        } catch {
            tunnel.stop()
            wantsConnection = false
            isConnected = false
            banner = diagnostics.fail(error)
        }
    }

    private func establishSSHConnection() async throws {
        diagnostics = ConnectionDiagnostics()
        diagnostics.update(.configuration, .running)
        let config = try sshConfiguration.validated()
        diagnostics.update(.configuration, .passed, detail: "格式有效；服务器身份仍需 SSH 实际校验。")
        diagnostics.update(.deviceKey, .running)
        await prepareDeviceIdentity()
        guard let identity = deviceIdentity else { throw identityError ?? SSHConnectionError.process("设备密钥不可用，请检查钥匙串授权。") }
        diagnostics.update(.deviceKey, .passed, detail: "使用本机钥匙串设备密钥。")
        diagnostics.update(.ssh, .running)
        let url = try await tunnel.start(configuration: config, identity: identity)
        diagnostics.update(.ssh, .passed, detail: "设备公钥已认证；服务器公钥与配置一致。")
        try Task.checkCancellation()
        var localSettings = ConnectionSettings.default
        localSettings.host = "127.0.0.1"
        localSettings.port = config.localPort
        localSettings.username = config.user
        localSettings.password = ""
        let client = config.backend == .hermes ? HermesClient(settings: localSettings) : nil
        let status: GatewayStatus
        diagnostics.update(.agent, .running)
        if let client {
            status = try await client.probe()
        } else {
            status = try await OpenClawProbe.probe(config)
        }
        diagnostics.update(.agent, .passed, detail: "健康接口通过；网页登录和模型回答需要你另行确认。")
        try Task.checkCancellation()
        guard wantsConnection else { throw CancellationError() }
        self.settings = localSettings
        self.client = client
        self.status = status
        signedInAs = config.user
        dashboardURL = url
        sshConfiguration = config
        UserDefaults.standard.set(try JSONEncoder().encode(config), forKey: sshSettingsKey)
        banner = nil
        isConnected = true
    }

    private func reconnectAfterTunnelExit() {
        guard wantsConnection, !isConnecting else { return }
        isConnected = false
        dashboardURL = nil
        client = nil
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            self.isConnecting = true
            defer { self.isConnecting = false }
            for (index, delay) in [1, 3, 8].enumerated() {
                do {
                    self.banner = "SSH 已断开，正在重连（\(index + 1)/3）"
                    try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                    try await self.establishSSHConnection()
                    return
                } catch {
                    self.tunnel.stop()
                    if Task.isCancelled || !self.wantsConnection { return }
                    self.banner = self.diagnostics.fail(error)
                }
            }
            self.wantsConnection = false
        }
    }

    func refreshStatus() async {
        guard isConnected else { return }
        diagnostics.update(.agent, .running)
        do {
            if sshConfiguration.backend == .openclaw {
                status = try await OpenClawProbe.probe(sshConfiguration)
            } else if let client {
                status = try await client.probe()
            }
            diagnostics.update(.agent, .passed, detail: "健康接口通过；网页登录和模型回答需要你另行确认。")
            banner = nil
        } catch {
            banner = diagnostics.fail(error)
        }
    }

    func disconnect() {
        wantsConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        tunnel.stop()
        refreshTask?.cancel()
        refreshTask = nil
        AppStateEventBus.handler = nil
        if let client {
            Task { await client.disconnect() }
        }
        client = nil
        isConnected = false
        dashboardURL = nil
        sessions = []
        messages = []
        selectedSessionID = nil
        liveSessionID = nil
        status = nil
    }

    func openSession(_ id: String) async {
        selectedSessionID = id
        liveSessionID = nil
        do {
            messages = try await client?.messages(sessionID: id) ?? []
        } catch {
            banner = error.localizedDescription
        }
    }

    func newChat() async {
        guard let client else { return }
        do {
            let bound = try await client.createSession()
            liveSessionID = bound.liveID
            selectedSessionID = bound.storedID
            messages = []
            try await reloadSessions()
        } catch {
            banner = error.localizedDescription
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client else { return }
        draft = ""
        isSending = true
        defer { isSending = false }
        do {
            let bound = try await bindLiveSession()
            liveSessionID = bound.liveID
            selectedSessionID = bound.storedID
            messages.append(
                ChatMessage(id: UUID().uuidString, role: .user, text: text, isStreaming: false)
            )
            messages.append(
                ChatMessage(id: "stream-\(bound.liveID)", role: .assistant, text: "", isStreaming: true)
            )
            try await client.submit(sessionID: bound.liveID, text: text)
        } catch {
            banner = error.localizedDescription
            messages.removeAll { $0.isStreaming }
        }
    }

    private func bindLiveSession() async throws -> HermesClient.BoundSession {
        guard let client else { throw HermlandError.disconnected }
        if let liveSessionID {
            return HermesClient.BoundSession(
                liveID: liveSessionID,
                storedID: selectedSessionID ?? liveSessionID
            )
        }
        if let selectedSessionID {
            return try await client.resumeSession(selectedSessionID)
        }
        return try await client.createSession()
    }

    private func reloadSessions() async throws {
        sessions = try await client?.listSessions() ?? []
    }

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await self.refreshQuietly()
            }
        }
    }

    private func refreshQuietly() async {
        guard let client, isConnected else { return }
        if let status = try? await client.probe() {
            self.status = status
        }
        if let sessions = try? await client.listSessions() {
            self.sessions = sessions
        }
    }

    private func handleEvent(type: String, sessionID: String, payload: JSONValue) {
        let current = liveSessionID ?? selectedSessionID
        if !sessionID.isEmpty, let current, sessionID != current { return }
        switch type {
        case "message.delta":
            appendStream(payload.textContent)
        case "message.complete":
            finishStream(payload["text"]?.string ?? payload.textContent)
            Task { try? await reloadSessions() }
        case "error":
            banner = payload["message"]?.string ?? payload.textContent
            finishStream(nil)
        default:
            break
        }
    }

    private func appendStream(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        if let index = messages.lastIndex(where: { $0.isStreaming }) {
            messages[index].text += chunk
        } else {
            messages.append(
                ChatMessage(id: "stream-\(UUID().uuidString)", role: .assistant, text: chunk, isStreaming: true)
            )
        }
    }

    private func finishStream(_ text: String?) {
        if let index = messages.lastIndex(where: { $0.isStreaming }) {
            if let text, !text.isEmpty {
                messages[index].text = text
            }
            messages[index].isStreaming = false
            if messages[index].text.isEmpty {
                messages.remove(at: index)
            }
        }
    }

    func openInBrowser() async {
        if isConnected, let url = dashboardURL {
            if sshConfiguration.backend == .openclaw {
                banner = "外部浏览器不使用 App 的隔离存储。请只在专用浏览器配置中打开，并确认当前 Gateway；不要复用其他服务器的令牌。"
                return
            }
            NSWorkspace.shared.open(url)
        }
    }
}
