import SwiftUI
import UniformTypeIdentifiers

struct OnboardingActions: View {
    @ObservedObject var store: AppState
    let purpose: SetupPurpose
    @State private var promptCopied = false
    @State private var preparing = false
    @State private var requestID = UUID()
    @State private var exporting = false
    @State private var guide: String?
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(preparing ? "准备公钥…" : (promptCopied ? "配置材料已复制" : "复制配置材料")) { copyRequest() }
                    .buttonStyle(.borderedProminent).tint(HermlandColor.accent).disabled(preparing)
                Button(exporting ? "正在导出…" : "导出配置工具") { export() }.disabled(exporting)
                Button("手动步骤") {
                    do { guide = try SetupResources.guide() }
                    catch { notice = "指引资源缺失，请使用仓库 docs/快速开始.md。" }
                }
            }
            Text("包含这台电脑的公钥、指纹和指令，不含私钥。手动发给你平时使用的 \(store.sshConfiguration.backend.title) 或可信管理员，不要发到尚未连通的 Hermland。")
                .font(.caption).foregroundStyle(HermlandColor.secondary)
            if let notice { Text(notice).font(.caption).textSelection(.enabled) }
        }
        .onChange(of: store.sshConfiguration.backend) { _, _ in invalidateCopy() }
        .onChange(of: purpose) { _, _ in invalidateCopy() }
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
        Task {
            defer { preparing = false }
            await store.prepareDeviceIdentity()
            do {
                let request = try OnboardingInstructions.request(for: backend, purpose: selectedPurpose,
                                                               publicKey: store.devicePublicKey)
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
                try await Task.detached(priority: .userInitiated) { try SetupResources.export(to: destination) }.value
                notice = "已导出配置工具与说明。解压后交给常驻 Mac 上的 Agent；不含密钥或令牌。"
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
                    Image(systemName: symbol(check.result)).foregroundStyle(color(check.result)).frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(check.phase.title)
                            Spacer()
                            Text(check.result.rawValue).foregroundStyle(color(check.result))
                        }.font(.caption)
                        if !check.detail.isEmpty {
                            Text(check.detail).font(.caption).foregroundStyle(HermlandColor.secondary)
                        }
                    }
                }
            }
            Text("最后请在原网页完成登录，再发送一条消息验证模型回答。此检查不发送模型请求。")
                .font(.caption).foregroundStyle(HermlandColor.secondary)
            Button(copied ? "检查结果已复制" : "复制检查结果") {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(diagnostics.report(backend: backend, version: version), forType: .string)
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
