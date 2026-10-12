import SwiftUI
import UniformTypeIdentifiers

struct ConnectView: View {
    @ObservedObject var store: AppState
    @State private var importing = false
    @State private var copied = false
    @State private var manual = false
    @State private var purpose: SetupPurpose = .firstSetup
    @State private var pendingConfiguration: SSHConfiguration?

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
                Picker("这次要做什么", selection: $purpose) {
                    ForEach(SetupPurpose.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                step(1, "复制材料，发给已有 Agent") {
                    Picker("已有的 Agent", selection: $store.sshConfiguration.backend) {
                        ForEach(AgentBackend.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                        .onChange(of: store.sshConfiguration.backend) { _, backend in
                            if backend == .hermes { store.sshConfiguration.controlUIPath = "/" }
                        }
                    OnboardingActions(store: store, purpose: purpose)
                    Text(purpose == .firstSetup
                         ? "已有服务和隧道就复用，只补缺失组件。没有执行权限时，按手动步骤完成。"
                         : "只为这台电脑增加授权。不重装 Agent，不重建常驻机隧道。")
                        .font(.caption).foregroundStyle(HermlandColor.secondary)
                }
                step(2, "核对指纹，明确确认授权") {
                    Text("Agent 或管理员报告要授权的电脑和指纹后，由你明确确认。复制材料不等于批准连接。")
                        .font(.callout)
                    if let fingerprint = SSHConfiguration.fingerprint(store.devicePublicKey) {
                        Text(fingerprint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    DisclosureGroup("只需公钥？单独复制") {
                        Button(copied ? "公钥已复制" : "复制设备公钥") {
                            Task {
                                await store.copyDevicePublicKey()
                                copied = !store.devicePublicKey.isEmpty
                            }
                        }
                    }
                    Text("私钥留在本机钥匙串。没有主动申请或自动审批入口。")
                        .font(.caption).foregroundStyle(HermlandColor.secondary)
                }
                step(3, "导入配置，检查后开始使用") {
                    HStack {
                        Button("导入并检查…") { importing = true }
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
                    Button { Task { await store.connect() } } label: {
                        HStack {
                            if store.isConnecting { ProgressView().controlSize(.small) }
                            Text(store.isConnecting ? "正在检查…" : "检查已有配置")
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
            case .success(let url):
                do {
                    pendingConfiguration = try store.readSSHConfiguration(from: url)
                    store.banner = nil
                } catch { store.banner = error.localizedDescription }
            case .failure: store.banner = "配置文件未导入。请重新选择管理员提供的 JSON。"
            }
        }
        .sheet(isPresented: Binding(get: { pendingConfiguration != nil },
                                    set: { if !$0 { pendingConfiguration = nil } })) {
            if let configuration = pendingConfiguration {
                VStack(alignment: .leading, spacing: 18) {
                    Text("确认管理员返回的配置").font(.title2)
                    Text("只有你确认文件来自可信管理员后，才会替换配置并连接。请通过原可信渠道核对服务器指纹。")
                        .foregroundStyle(HermlandColor.secondary)
                    Text("\(configuration.backend.title) · \(configuration.displayAddress)")
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Text(SSHConfiguration.fingerprint(configuration.serverPublicKey) ?? "")
                        .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button("取消") { pendingConfiguration = nil }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("来源可信，连接并检查") {
                            store.sshConfiguration = configuration
                            pendingConfiguration = nil
                            Task { await store.connect() }
                        }.buttonStyle(.borderedProminent).tint(HermlandColor.accent)
                    }
                }.padding(28).frame(width: 620)
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
