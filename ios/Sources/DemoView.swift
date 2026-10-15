import SwiftUI
import HermlandCore

/// Explicit, local-only examples. This view cannot authorize a device or open a tunnel.
struct DemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var backend: AgentBackend = .hermes
    @State private var selectedCheck = 0
    @State private var showExplanation = false
    private let stages = [
        ("配置格式", "检查管理员返回的服务器、设备账户和界面路径。配置中不含设备私钥或网页登录令牌。"),
        ("本机密钥", "这台 iPhone 自己生成密钥。只分享公钥，私钥保留在本机钥匙串。"),
        ("SSH 授权与服务器身份", "服务器必须已手动授权本机公钥。App 同时核对完整服务器公钥，不接受身份不一致的服务器。"),
        ("Agent 服务", "通过隧道读取健康状态和网页。检查通过不等于完成网页登录，也不代表模型已经回答。")
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("离线演示 · 未建立连接", systemImage: "info.circle.fill")
                        .font(.callout.weight(.semibold)).foregroundStyle(Palette.accent)
                    Text("了解连接，再接入自己的 Agent").font(.title2.bold())
                    Text("这里的状态和会话都是示例。不连接服务器、不调用模型，也不会修改你的配置。").foregroundStyle(.secondary)
                    Picker("示例后端", selection: $backend) {
                        ForEach(AgentBackend.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 18) {
                        Text("连接检查示例").font(.headline)
                        ForEach(stages.indices, id: \.self) { index in
                            Button { selectedCheck = index } label: {
                                HStack {
                                    Image(systemName: selectedCheck == index ? "checkmark.circle.fill" : "circle")
                                    Text(stages[index].0)
                                    Spacer()
                                    Text("查看原理").font(.caption)
                                }
                            }.buttonStyle(.plain)
                                .foregroundStyle(selectedCheck == index ? Palette.accent : .primary)
                        }
                        Text(stages[selectedCheck].1).font(.callout).foregroundStyle(.secondary)
                    }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Text("\(backend.title) · 示例会话").font(.headline); Spacer(); Text("离线").font(.caption).foregroundStyle(.secondary) }
                        bubble("我能用已有的 Agent 吗？", user: true)
                        bubble("可以。Hermland 连接你的原界面，不迁移模型、配置和会话。真实连接后，功能和回答由你自己的 \(backend.title) 提供。", user: false)
                        if showExplanation {
                            bubble("断网或进入后台后会怎样？", user: true)
                            bubble("返回前台后恢复隧道，原任务是否继续取决于 Agent。Hermland 不会自动重发你的消息。", user: false)
                        } else {
                            Button("查看后台恢复示例") { showExplanation = true }.font(.callout.weight(.semibold))
                        }
                        Text("本页使用原生示例内容，不是上游 WebUI 截图，也不是真实模型回复。").font(.caption).foregroundStyle(.secondary)
                    }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
                    Text("正式连接：分享公钥 → 手动确认授权 → 导入并核对配置。演示不会改变这项要求。").font(.footnote).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(Palette.canvas)
                .navigationTitle("离线演示").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.tint(Palette.accent)
    }
    private func bubble(_ text: String, user: Bool) -> some View {
        HStack {
            if user { Spacer(minLength: 40) }
            Text(text).font(.callout).padding(14)
                .background(user ? Palette.accent.opacity(0.12) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 16))
            if !user { Spacer(minLength: 20) }
        }
    }
}
