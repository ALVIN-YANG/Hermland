import HermlandCore
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @ObservedObject var store: ConnectionStore
    @State private var importing = false
    @State private var showDemo = false
    var body: some View {
        Group {
            if store.configuration == nil && !store.connecting
                && store.checks.allSatisfy({ $0.result == .waiting })
            {
                NavigationStack {
                    MobileSetupScreen(store: store, importAction: { importing = true }, demoAction: { showDemo = true })
                }
            } else {
                TabView(selection: $store.tab) {
                    AgentPage(store: store).tabItem { Label("Agent", systemImage: "bubble.left.fill") }.tag(0)
                    NavigationStack { ConnectionView(store: store, importAction: { importing = true }) }
                        .tabItem { Label("连接", systemImage: "link") }.tag(1)
                }
            }
        }
        .tint(Palette.accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { store.review(url) }
        }
        .sheet(
            isPresented: Binding(
                get: { store.candidate != nil }, set: { if !$0 { store.candidate = nil } })
        ) {
            if let candidate = store.candidate {
                ImportReview(configuration: candidate, filename: store.candidateFilename, accept: store.acceptCandidate)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.sharingMaterial != nil }, set: { if !$0 { store.sharingMaterial = nil } })
        ) {
            if let text = store.sharingMaterial { ShareSheet(text: text) }
        }
        .sheet(isPresented: $showDemo) { DemoView() }
    }

}

struct ImportReview: View {
    let configuration: SSHConfiguration
    var filename = "连接配置.json"
    let accept: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                SetupConnectionReview(
                    configuration: configuration, deviceName: "这台 iPhone", filename: filename,
                    cancel: { dismiss() }, accept: accept
                ).padding(24).frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("核对连接")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct ConnectionView: View {
    @ObservedObject var store: ConnectionStore
    let importAction: () -> Void
    @State private var forgetting = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    MessengerIcon(size: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.configuration?.backend.title ?? store.backend.title).font(.title2.bold())
                        Label(
                            store.connecting ? "正在连接" : store.connected ? "已连接" : "未连接",
                            systemImage: store.connected ? "checkmark.circle.fill" : "link"
                        )
                        .foregroundStyle(store.connected ? Palette.accent : Color.secondary)
                    }
                }.padding(.vertical, 8)
                if let error = store.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            Section("连接检查") {
                ForEach(store.checks) { check in
                    HStack(spacing: 12) {
                        Text(check.title)
                        Spacer()
                        if check.result == .running {
                            ProgressView()
                        } else {
                            Image(
                                systemName: check.result == .passed
                                    ? "checkmark.circle.fill"
                                    : check.result == .failed ? "exclamationmark.circle" : "circle")
                        }
                        Text(check.result.rawValue).font(.callout)
                    }.foregroundStyle(
                        check.result == .passed ? Palette.accent : check.result == .failed ? .red : .primary)
                }
                Text("网页登录与模型回答需在原页面另行确认。").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                if store.connecting {
                    Button("取消连接", action: store.disconnect)
                } else if store.connected {
                    Button("断开连接", action: store.disconnect)
                } else if store.configuration != nil {
                    Button("重新连接", action: store.retry)
                }
                Button("导入连接配置", action: importAction).disabled(store.connecting)
            } footer: {
                Text("回到前台后恢复连接，不会自动重发消息。断开连接不等于撤销授权。")
            }
            Section("这台 iPhone") {
                if let key = store.identity {
                    DisclosureGroup("查看公钥与指纹") {
                        Text(key.fingerprint).font(.system(.caption, design: .monospaced)).textSelection(
                            .enabled)
                        Text(key.publicKey).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
                Button("分享配置材料", action: store.prepareShare)
                NavigationLink("使用与隐私说明") { HelpView() }
                if store.configuration != nil {
                    Button("移除此连接配置", role: .destructive) { forgetting = true }
                }
            }
        }
        .navigationTitle("连接")
        .confirmationDialog("移除本机连接配置？", isPresented: $forgetting, titleVisibility: .visible) {
            Button("移除配置", role: .destructive, action: store.forget)
        } message: {
            Text("服务器授权仍然有效。永久停用或丢失设备时，请让管理员撤销本机公钥。")
        }
    }
}

struct HelpView: View {
    var body: some View {
        List {
            Section("使用") {
                Text("先把本机公钥手动发给已有 Agent 或可信管理员。由你确认授权后，导入返回的连接配置。")
                Text("Hermes 使用原 WebUI，OpenClaw 使用原 Control UI。SSH 通过后仍须完成原网页登录。")
                Link(
                    "配置指引",
                    destination: URL(string: "https://github.com/ALVIN-YANG/Hermland/blob/main/docs/快速开始.md")!
                )
            }
            Section("连接与权限") {
                Text("手机进入后台后连接可能中断，返回时重连。原任务是否继续取决于 Agent；消息不会自动重发。")
                Text("没有自动申请或审批。撤销设备授权需要管理员操作。")
            }
            Section("隐私") {
                Text("Hermland 不运营聊天服务器，不收集分析数据。连接配置留在本机，设备私钥保存在本机钥匙串。")
                Text("你配置的 VPS 和 Agent 会处理连接及聊天内容。双 SSH 分段加密，VPS 管理员须可信；原 Agent 和模型服务的隐私规则仍然适用。")
                Text("移除配置只清除本机连接记录；原会话由你的 Agent 管理。")
                Link(
                    "完整隐私说明", destination: URL(string: "https://alvin-yang.github.io/Hermland/privacy.html")!)
                Link("项目与支持", destination: URL(string: "https://github.com/ALVIN-YANG/Hermland")!)
                NavigationLink("开源组件与许可证") { ThirdPartyNoticesView() }
            }
        }.navigationTitle("使用与隐私说明").navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThirdPartyNoticesView: View {
    private let notices =
        Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "许可证文件不可用。"
    var body: some View {
        ScrollView {
            Text(notices).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
        }.navigationTitle("开源组件").navigationBarTitleDisplayMode(.inline)
    }
}
