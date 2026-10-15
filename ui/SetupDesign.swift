import SwiftUI

enum SetupTheme {
    static let accent = Color("SetupAccent")
    static let buttonFill = Color(red: 0.26, green: 0.40, blue: 0.57)
    static let amber = Color(red: 0.91, green: 0.73, blue: 0.45)
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.075, green: 0.095, blue: 0.14) : Color(red: 0.97, green: 0.98, blue: 0.99)
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.115, green: 0.14, blue: 0.19) : .white
    }
}

struct SetupPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(.white)
            .background(
                SetupTheme.buttonFill.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SetupScene: View {
    var deviceName: String
    var showLabels = true
    var body: some View {
        VStack(spacing: 12) {
            Image("ConnectionScene").resizable().scaledToFit().accessibilityHidden(true)
            if showLabels {
                HStack(alignment: .top) {
                    Text("家里的 Mac").frame(maxWidth: .infinity)
                    Text("你的云服务器").frame(maxWidth: .infinity)
                    Text(deviceName).frame(maxWidth: .infinity)
                }.font(.callout).foregroundStyle(.secondary)
                Text("Agent 留在家里，服务器只负责中转。")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
    }
}

struct SetupHeading: View {
    let title: String
    let subtitle: String
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 32
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: titleSize, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ConnectionPrinciplesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SetupHeading(title: "还是家里的那个 Agent", subtitle: "Hermland 只提供远程入口，不复制一套模型或会话。")
                    SetupScene(deviceName: "随身设备").frame(maxWidth: 500)
                    explanation("家里的 Mac", "继续运行原来的 Hermes 或 OpenClaw，保留原配置、记忆和会话。它需要开机、联网且不睡眠。")
                    explanation(
                        "你自己的云服务器", "在两个网络之间转接连接，不需要域名，也不把 Agent 网页公开到互联网。双 SSH 分段加密，VPS 管理员仍须可信，并非绕过 VPS 的端到端加密。")
                    explanation("只有你明确授权的设备", "每台设备使用自己的密钥。私钥留在本机钥匙串；你手动发送公钥，管理员核对并得到你确认后才授权。没有公网申请或自动审批。")
                    explanation("连接通了，不等于登录完成", "App 检查服务器身份、设备授权和 Agent 服务。之后仍要在原网页完成登录，再由你发消息确认回答；检查不会自动发模型消息。")
                    Link("隐私与支持", destination: URL(string: "https://alvin-yang.github.io/Hermland/privacy.html")!)
                }.padding(28).frame(maxWidth: 660)
            }.navigationTitle("连接原理")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
    private func explanation(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
