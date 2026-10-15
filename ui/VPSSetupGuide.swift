import SwiftUI

/// Instructions only. This view never logs in to, installs on, or authorizes a server.
struct VPSSetupGuide: View {
    let backendTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SetupHeading(title: "先准备，再回 App", subtitle: "VPS 是你租用的云服务器，只转接两台 Mac 的连接。Agent、模型和会话仍留在家里。")
                    SetupInstructionRow(number: "1", title: "创建或复用一台服务器", detail: "在你信任的云厂商选择 Debian / Ubuntu。已有合适服务器可以复用，不必再买；费用和账号由你自己管理，不需要 GPU 或域名。")
                    SetupInstructionRow(number: "2", title: "记下公网 IP 和 SSH 端口", detail: "在云厂商控制台查看，SSH 端口通常为 22。IP 和端口稍后填进 App；管理员账号和登录凭据自己保管，不填进连接卡。")
                    SetupInstructionRow(number: "3", title: "核对身份，成功登录一次", detail: "SSH 是服务器的安全管理连接。你或可信管理员先用官方控制台核对服务器指纹，再通过 SSH 登录，并确认有 root / sudo 管理权限。不会操作就展开下面的说明，或请可信管理员协助。")
                    Text("准备好的标志：知道公网 IP、SSH 端口，而且你或管理员已核对身份、成功登录。仅填地址或勾选确认，不代表 App 已验证连接。")
                        .foregroundStyle(SetupTheme.accent)
                    DisclosureGroup("第一次用 SSH？跟着核对和登录") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("先在云厂商提供的可信控制台终端登录这台服务器，执行下面的只读命令。记下输出的 SHA256:…，它是服务器身份的识别码。")
                            command("ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
                            Text("再在管理用的 Mac 打开「终端」，将下面示例中的端口、用户名和 IP 换成真实值后执行。不要照抄占位文字。")
                            command("ssh -o HostKeyAlgorithms=ssh-ed25519 -p 22 管理员用户名@服务器公网IP")
                            Text("首次显示的指纹须与控制台一致，才接受连接；密码或密钥口令由你自己输入。成功进入服务器命令行，再确认管理权限，退出用 exit。")
                            Text("指纹不同、旧身份突然变化、找不到公钥文件或不能登录时，先停下找管理员核实。不要输入未知密码，不要删记录或关闭校验来绕过提示。不要把密码、管理员私钥或模型密钥发给 Agent。")
                                .foregroundStyle(SetupTheme.secondary)
                        }.font(SetupTheme.supportFont).padding(.top, 16)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("准备好之后，回到 App").font(SetupTheme.labelFont)
                        Text("填 IP 和端口 → 复制连接卡 → 发给你平时使用的 \(backendTitle)。有执行权限时，它协助配置中转；没有权限时，由你或管理员执行它给出的命令。")
                        Text("核对设备名和公钥指纹，明确同意授权，再收回 .json 连接文件。App 本身不会安装服务器软件，也不会自动批准设备。")
                            .foregroundStyle(SetupTheme.secondary)
                    }
                    DisclosureGroup("我想手动配置：完整命令在哪？") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("在 Mac App 的连接卡页展开「Agent 无法执行？查看手动方式」，可导出工具包和查看离线指南。按指南分别在家里 Mac、VPS 和客户端执行，每步检查通过再继续。")
                            Link("打开完整手动部署指南", destination: URL(string: "https://github.com/ALVIN-YANG/Hermland/blob/main/docs/快速开始.md")!)
                        }.font(SetupTheme.supportFont).padding(.top, 12)
                    }
                    Text("只为 Hermland 允许 SSH 入口，不公开 8787、18789、19119 或 19121；其他服务的必要规则保留。两段 SSH 不是两台 Mac 之间端到端加密，VPS 管理员必须可信。")
                        .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
                    Link("网页版本：服务器准备指南", destination: URL(string: "https://github.com/ALVIN-YANG/Hermland/blob/main/docs/准备中转服务器.md")!)
                }
                .padding(28).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }
            .font(SetupTheme.bodyFont).tint(SetupTheme.accent)
            .navigationTitle("准备你的云服务器")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func command(_ text: String) -> some View {
        Text(text).font(SetupTheme.codeFont).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(SetupTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
