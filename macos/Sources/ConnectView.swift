import SwiftUI
import UniformTypeIdentifiers

struct ConnectView: View {
    @ObservedObject var store: AppState
    @State private var importing = false
    @State private var manual = false
    @State private var pendingConfiguration: SSHConfiguration?
    @State private var filename = "连接配置.json"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            SetupFlowView(
                backend: $store.sshConfiguration.backend, deviceName: "这台 Mac",
                initialPage: store.sshConfiguration.host.isEmpty ? .welcome : .connection,
                message: store.banner, isConnecting: store.isConnecting, importAction: { importing = true }
            ) { context in
                OnboardingActions(
                    store: store, purpose: context.firstSetup ? .firstSetup : .additionalDevice,
                    server: context.serverForRequest)
            } connection: { wide in
                connection(wide: wide)
            }
            .opacity(pendingConfiguration == nil ? 1 : 0)
            .allowsHitTesting(pendingConfiguration == nil)
            .accessibilityHidden(pendingConfiguration != nil)
            if let configuration = pendingConfiguration {
                ScrollView {
                    HStack(spacing: 36) {
                        SetupConnectionReview(
                            configuration: configuration, deviceName: "这台 Mac", filename: filename,
                            cancel: { pendingConfiguration = nil },
                            accept: {
                                store.sshConfiguration = configuration
                                pendingConfiguration = nil
                                Task { await store.connect() }
                            }
                        ).frame(maxWidth: 640)
                        SetupScene(deviceName: "这台 Mac", showLabels: false).frame(maxWidth: 320)
                    }.padding(44).frame(maxWidth: 1160).frame(maxWidth: .infinity)
                }.background(SetupTheme.canvas(colorScheme))
            }
        }
        .disabled(store.isConnecting)
        .onChange(of: store.sshConfiguration.backend) { _, backend in
            if backend == .hermes { store.sshConfiguration.controlUIPath = "/" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let configuration = try store.readSSHConfiguration(from: url)
                    filename = url.lastPathComponent
                    pendingConfiguration = configuration
                    store.banner = nil
                } catch { store.banner = error.localizedDescription }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    store.banner = "配置文件未导入。请重新选择管理员返回的 JSON。"
                }
            }
        }
    }

    private func connection(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SetupHeading(
                title: store.isConnecting ? "正在检查连接" : "连接家里的 \(store.sshConfiguration.backend.title)",
                subtitle: "使用上次的连接配置，或导入管理员发回的新文件。")
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(store.sshConfiguration.displayAddress).font(.body).textSelection(.enabled)
                    Button("导入连接文件…") { importing = true }.controlSize(.large)
                    if let fingerprint = SSHConfiguration.fingerprint(store.sshConfiguration.serverPublicKey) {
                        DisclosureGroup("已保存的服务器指纹") {
                            Text(fingerprint).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    Button(store.isConnecting ? "正在检查…" : "连接并检查") {
                        Task { await store.connect() }
                    }.buttonStyle(SetupPrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    ConnectionChecksView(diagnostics: store.diagnostics, backend: store.sshConfiguration.backend)
                    DisclosureGroup("高级：手动填写连接参数", isExpanded: $manual) {
                        VStack(spacing: 12) {
                            field("服务器", text: $store.sshConfiguration.host, placeholder: "IP 或域名")
                            field("SSH 用户", text: $store.sshConfiguration.user, placeholder: "管理员提供的专用用户")
                            port("SSH 端口", value: $store.sshConfiguration.port)
                            field(
                                "服务器公钥", text: $store.sshConfiguration.serverPublicKey, placeholder: "ssh-ed25519 AAAA…"
                            )
                            port("VPS 本机端口", value: $store.sshConfiguration.remotePort)
                            port("App 本机端口", value: $store.sshConfiguration.localPort)
                            if store.sshConfiguration.backend == .openclaw {
                                field("界面路径", text: $store.sshConfiguration.controlUIPath, placeholder: "/")
                            }
                        }.padding(.top, 12)
                    }
                }.frame(maxWidth: 620)
                if wide { SetupScene(deviceName: "这台 Mac", showLabels: false).frame(maxWidth: 320) }
            }
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
