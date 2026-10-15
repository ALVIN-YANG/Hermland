import SwiftUI

#if os(iOS)
    import HermlandCore
#endif

struct SetupConnectionReview: View {
    let configuration: SSHConfiguration
    let deviceName: String
    let filename: String
    let cancel: () -> Void
    let accept: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SetupHeading(title: "核对来源，再连接", subtitle: "只导入你自己的 Agent 或可信管理员发回的文件。")
            HStack(spacing: 16) {
                Image(systemName: "doc.text").font(.title).foregroundStyle(SetupTheme.accent)
                Text(filename).font(SetupTheme.labelFont).lineLimit(2)
                Spacer()
                Button("取消导入", action: cancel)
            }
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("连接到", value: "家里的 \(configuration.backend.title)")
                LabeledContent("中转服务器", value: "\(configuration.host):\(configuration.port)")
                LabeledContent("设备", value: deviceName)
                DisclosureGroup("设备账户与转发路径") {
                    Text(
                        "\(configuration.user) · 远端本机端口 \(configuration.remotePort) · 界面 \(configuration.controlUIPath)"
                    )
                    .font(SetupTheme.supportFont).textSelection(.enabled)
                }
                Divider()
                Text("服务器指纹").font(SetupTheme.labelFont)
                Text(SSHConfiguration.fingerprint(configuration.serverPublicKey) ?? "无效指纹")
                    .font(SetupTheme.codeFont).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("通过可信渠道，与管理员提供的指纹核对。配置文件本身不能证明来源。")
                    .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
            }.padding(22).background(SetupTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 16))
            Button("来源可信，连接并检查", action: accept).buttonStyle(SetupPrimaryButtonStyle())
            Text("确认后才检查服务器身份、设备授权和 Agent 服务。检查通过后，沿用原网页登录，再发一条消息确认回复。")
                .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
        }
    }
}
