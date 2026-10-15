import SwiftUI
import UniformTypeIdentifiers

struct OnboardingActions: View {
    @ObservedObject var store: AppState
    let purpose: SetupPurpose
    var server: SetupServerDetails? = nil
    @State private var promptCopied = false
    @State private var preparing = false
    @State private var requestID = UUID()
    @State private var exporting = false
    @State private var guide: String?
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fingerprint = SSHConfiguration.fingerprint(store.devicePublicKey) {
                Text("本机公钥指纹").font(SetupTheme.supportFont)
                Text(fingerprint).font(SetupTheme.codeFont).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("授权前，与对方报告的这一串识别码核对。私钥留在本机钥匙串。")
                    .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
            }
            Button(preparing ? "准备连接卡…" : (promptCopied ? "连接卡已复制" : "复制连接卡")) { copyRequest() }
                .buttonStyle(SetupPrimaryButtonStyle()).disabled(preparing)
            Text(promptCopied ? "下一步：回到原 Agent 对话，粘贴并发送。这里还没有授权任何设备。" : "点击后只复制；不会自动发送、登录服务器或授权。")
                .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
            DisclosureGroup("查看公钥与完整指令") {
                if let request = try? OnboardingInstructions.request(
                    for: store.sshConfiguration.backend,
                    purpose: purpose, publicKey: store.devicePublicKey, server: server)
                {
                    Text(request).font(SetupTheme.codeFont).textSelection(.enabled)
                } else {
                    Text("复制连接卡时准备本机公钥；私钥留在钥匙串，不会发送。")
                        .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
                }
                Button("仅复制设备公钥") { Task { await store.copyDevicePublicKey() } }
            }
            DisclosureGroup("Agent 无法执行？查看手动方式") {
                Text("Agent 能取得项目源码时，无需发送工具包。否则导出工具包，发到家里的 Mac 解压；不能执行命令时，由你或管理员按部署指南操作。")
                    .font(SetupTheme.supportFont).foregroundStyle(HermlandColor.secondary)
                HStack {
                    Button(exporting ? "正在导出…" : "导出工具包…") { export() }.disabled(exporting)
                    Button("查看手动部署指南") {
                        do { guide = try SetupResources.guide() } catch {
                            notice = "指引资源缺失，请使用仓库 docs/快速开始.md。"
                        }
                    }
                }
            }
            if let notice { Text(notice).font(SetupTheme.supportFont).textSelection(.enabled) }
        }
        .onChange(of: store.sshConfiguration.backend) { _, _ in invalidateCopy() }
        .onChange(of: purpose) { _, _ in invalidateCopy() }
        .onChange(of: server) { _, _ in invalidateCopy() }
        .onDisappear { requestID = UUID() }
        .sheet(isPresented: Binding(get: { guide != nil }, set: { if !$0 { guide = nil } })) {
            VStack(alignment: .leading) {
                HStack {
                    Text("手动配置步骤").font(.title2)
                    Spacer()
                    Button("完成") { guide = nil }.keyboardShortcut(.cancelAction)
                }
                ScrollView {
                    Text(guide ?? "").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical)
                }
            }.padding(24).frame(width: 740, height: 620)
        }
    }

    private func copyRequest() {
        preparing = true
        promptCopied = false
        let operationID = UUID()
        requestID = operationID
        let backend = store.sshConfiguration.backend
        let selectedPurpose = purpose
        let selectedServer = server
        Task {
            defer { preparing = false }
            await store.prepareDeviceIdentity()
            do {
                let request = try OnboardingInstructions.request(
                    for: backend, purpose: selectedPurpose,
                    publicKey: store.devicePublicKey, server: selectedServer)
                // A changed selection must not show a success label for stale material.
                guard operationID == requestID, backend == store.sshConfiguration.backend else { return }
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setString(request, forType: .string) else {
                    throw SSHConnectionError.process("复制失败，请重试。")
                }
                promptCopied = true
                notice = nil
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    private func invalidateCopy() {
        requestID = UUID()
        promptCopied = false
        notice = nil
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "HermlandSetup.zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        exporting = true
        Task {
            defer { exporting = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try SetupResources.export(to: destination)
                }.value
                notice = "工具包已导出。请发到家里的 Mac 解压，让原 Agent 或管理员使用；不含密钥或令牌。"
            } catch {
                notice = "导出失败。请使用新文件名，或重新构建包含配置资源的 App。"
            }
        }
    }
}

struct ConnectionChecksView: View {
    let diagnostics: ConnectionDiagnostics
    let backend: AgentBackend
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(diagnostics.checks) { check in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol(check.result)).foregroundStyle(color(check.result)).frame(
                        width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(check.phase.title)
                            Spacer()
                            Text(check.result.rawValue).foregroundStyle(color(check.result))
                        }.font(SetupTheme.supportFont)
                        if !check.detail.isEmpty {
                            Text(check.detail).font(SetupTheme.supportFont).foregroundStyle(HermlandColor.secondary)
                        }
                    }
                }
            }
            Text("最后请在原网页完成登录，再发送一条消息验证模型回答。此检查不发送模型请求。")
                .font(SetupTheme.supportFont).foregroundStyle(HermlandColor.secondary)
            Button(copied ? "检查结果已复制" : "复制检查结果") {
                let version =
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    diagnostics.report(backend: backend, version: version), forType: .string)
                copied = true
            }.controlSize(.small)
        }.onChange(of: diagnostics) { _, _ in copied = false }
    }

    private func symbol(_ result: CheckResult) -> String {
        switch result {
        case .waiting: return "circle"
        case .running: return "ellipsis.circle"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }
    private func color(_ result: CheckResult) -> Color {
        switch result {
        case .passed: return Color(nsColor: .systemGreen)
        case .failed: return .red
        case .running: return .orange
        case .waiting: return HermlandColor.secondary
        }
    }
}
