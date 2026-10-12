import SwiftUI
import UniformTypeIdentifiers

struct ConnectView: View {
    @ObservedObject var store: AppState
    @State private var importing = false
    @State private var copied = false
    @State private var manual = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("连接你已有的 Agent")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("不迁移模型、记忆或会话。准备一次，以后打开就连。")
                        .foregroundStyle(HermlandColor.secondary)
                    Text("常驻 Mac · Debian / Ubuntu VPS · macOS 14+ 客户端")
                        .font(.caption).foregroundStyle(HermlandColor.secondary)
                }
                step(1, "让已有 Agent 协助配置") {
                    Picker("已有的 Agent", selection: $store.sshConfiguration.backend) {
                        ForEach(AgentBackend.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                        .onChange(of: store.sshConfiguration.backend) { _, backend in
                            if backend == .hermes { store.sshConfiguration.controlUIPath = "/" }
                        }
                    OnboardingActions(backend: store.sshConfiguration.backend)
                }
                step(2, "手动发送这台电脑的公钥") {
                    HStack {
                        Button(copied ? "公钥已复制" : "复制设备公钥") {
                            Task {
                                await store.copyDevicePublicKey()
                                copied = !store.devicePublicKey.isEmpty
                            }
                        }
                        Text("发给可信管理员，由你确认后授权。")
                            .font(.caption).foregroundStyle(HermlandColor.secondary)
                    }
                    if let fingerprint = SSHConfiguration.fingerprint(store.devicePublicKey) {
                        Text(fingerprint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    Text("私钥留在本机钥匙串。没有主动申请或自动审批入口。")
                        .font(.caption).foregroundStyle(HermlandColor.secondary)
                }
                step(3, "导入管理员返回的配置") {
                    HStack {
                        Button("导入连接配置") { importing = true }
                        if (try? store.sshConfiguration.validated()) != nil {
                            Label("格式有效", systemImage: "checkmark.circle")
                                .font(.caption).foregroundStyle(HermlandColor.accent)
                        }
                    }
                    if !store.sshConfiguration.host.isEmpty {
                        Text(store.sshConfiguration.displayAddress).font(.system(.callout, design: .monospaced))
                        if let fingerprint = SSHConfiguration.fingerprint(store.sshConfiguration.serverPublicKey) {
                            Text("服务器指纹：\(fingerprint)")
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    Text("核对配置来源。格式有效不代表服务器身份已验证。")
                        .font(.caption).foregroundStyle(HermlandColor.secondary)
                    DisclosureGroup("手动填写或修改", isExpanded: $manual) {
                        VStack(alignment: .leading, spacing: 12) {
                            field("服务器", text: $store.sshConfiguration.host, placeholder: "IP 或域名")
                            field("SSH 用户", text: $store.sshConfiguration.user, placeholder: "管理员提供的专用用户")
                            port("SSH 端口", value: $store.sshConfiguration.port)
                            field("服务器公钥", text: $store.sshConfiguration.serverPublicKey, placeholder: "ssh-ed25519 AAAA…")
                            port("VPS 本机端口", value: $store.sshConfiguration.remotePort)
                            port("App 本机端口", value: $store.sshConfiguration.localPort)
                            if store.sshConfiguration.backend == .openclaw {
                                field("界面路径", text: $store.sshConfiguration.controlUIPath, placeholder: "/")
                            }
                        }.padding(.top, 10)
                    }
                }
                step(4, "连接并逐项检查") {
                    Button { Task { await store.connect() } } label: {
                        HStack {
                            if store.isConnecting { ProgressView().controlSize(.small) }
                            Text(store.isConnecting ? "正在检查…" : "连接并检查")
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(HermlandColor.accent)
                    .controlSize(.large).keyboardShortcut(.defaultAction)
                    .disabled(store.sshConfiguration.host.isEmpty)
                    ConnectionChecksView(diagnostics: store.diagnostics, backend: store.sshConfiguration.backend)
                    if let banner = store.banner {
                        Text(banner).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: 580).padding(36).frame(maxWidth: .infinity)
            .disabled(store.isConnecting)
        }
        .background(HermlandColor.canvas)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): store.importSSHConfiguration(from: url)
            case .failure: store.banner = "配置文件未导入。请重新选择管理员提供的 JSON。"
            }
        }
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(String(number)).font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(HermlandColor.accent)
                .frame(width: 28, height: 28).background(HermlandColor.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                content()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func port(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            TextField("端口", value: value, format: .number).textFieldStyle(.roundedBorder)
        }
    }
}
