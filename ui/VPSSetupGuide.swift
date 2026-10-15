import SwiftUI

/// Instructions only. This view never logs in to, installs on, or authorizes a server.
struct VPSSetupGuide: View {
    let backendTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("VPS 是你自己的云服务器，用来中转这台设备与家里 Mac 的连接。Agent 和会话仍留在家里，不搬到 VPS。")
                    Text("首次使用要配置一次。已有设备能连接时，只增加新设备授权，不重新部署服务器。")
                        .foregroundStyle(.secondary)
                }
                Section("还没有服务器？先这样准备") {
                    instruction("1", "在你选择的云服务商控制台创建一台 Debian / Ubuntu 服务器。Agent 不搬过去，不需要为它购买 GPU。购买、计费和账号由你自己管理。")
                    instruction("2", "记下公网 IP、SSH 端口和管理员账户。Hermland 不需要域名；只为本项目允许 SSH 端口，不公开 Agent 网页。")
                    instruction(
                        "3", "按云服务商说明配置你的管理 SSH 公钥。通过已登录的官方控制台取得服务器主机公钥，再与首次 SSH 登录显示的指纹核对；不要直接接受未知指纹。先确认自己或管理员能登录。")
                    Text("不会管理服务器时，请可信管理员协助。不要把管理员密码或私钥发到聊天，不要为安装临时关闭主机身份校验。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("已经有服务器？核对这些") {
                    Label("一台 Debian / Ubuntu 云服务器", systemImage: "cloud")
                    Label("服务器 IP、SSH 端口和管理员账户", systemImage: "list.bullet")
                    Label("已经核对服务器身份的管理员 SSH 登录", systemImage: "lock.shield")
                    Text("管理员可以是你自己。还没有服务器或不能登录时，先完成这项准备；Hermland 不代购服务器，也不提供管理员账号。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("推荐：让家里的 Agent 协助") {
                    instruction("1", "在 App 点「开始连接」，填写准备好的服务器信息，然后复制或分享连接卡，发给你原来使用的 \(backendTitle)。")
                    instruction("2", "告诉它 VPS 的 IP、SSH 端口，以及可使用的已有可信管理连接。不要把密码、管理员私钥或模型 API Key 放进聊天。")
                    instruction("3", "Agent 有现成执行权限时可协助部署；没有时，由你或管理员在 VPS 执行它给出的命令。不为此给 Agent 永久管理权限。")
                    instruction("4", "分别核对家里 Mac 和本设备的公钥，明确确认后才授权。完成后，向对方索取 .json 连接文件，回 App 导入。")
                    Text("App 本身不会远程执行安装命令，也不会自动批准设备。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("自己配置：命令在哪执行？") {
                    DisclosureGroup("安装 VPS 管理工具") {
                        Text(
                            "先从 Mac App 导出工具包并解压。以下是在管理电脑、工具包根目录执行的示例，适用于已核对身份且能以 root 登录的 VPS；VPS_IP 要换成你的地址。使用 sudo 管理账户时，请由管理员按实际账户调整，不要为示例开启 root 密码登录。"
                        )
                        .font(.callout)
                        command(
                            "scp -r deploy root@VPS_IP:/root/hermland-deploy\nssh root@VPS_IP 'bash /root/hermland-deploy/setup-vps.sh'"
                        )
                        Text("成功应打印 PASS，工具安装到 /opt/hermland。这只安装管理工具，尚未授权设备，也没有完成整条连接。发现冲突或旧版本时先停下核对，不删除旧配置、不盲目升级。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("之后还需在家里 Mac 建立到 VPS 的连接，在 VPS 分别授权中转公钥和客户端公钥，验证中转，再导出连接文件。完整命令按部署指南逐步执行；每步 PASS 后才继续。")
                        .font(.callout)
                    Link(
                        "打开完整手动部署指南",
                        destination: URL(string: "https://github.com/ALVIN-YANG/Hermland/blob/main/docs/快速开始.md")!)
                }
                Section("怎样确认 VPS 配置完成？") {
                    Text("在 VPS 上执行只读检查：")
                    command(
                        "python3 /opt/hermland/hermland.py check"
                            + (backendTitle == "OpenClaw" ? " --backend openclaw" : "") + " --port 19119")
                    Text("应打印 PASS，转发端口只在 VPS 本机监听。然后确认对应设备已经授权，并收到它专用的连接文件。最后由你在 App 完成原网页登录并验证回答；PASS 不代表模型已经回答。")
                        .font(.callout)
                }
                Section("不要开放这些端口") {
                    Text(
                        "Hermland 只需要公网 SSH 端口，默认 22。不要把本项目的 8787、18789、19119 或 19121 开放到公网；它们分别用于原 Agent、本机中转或 App 本地连接。不需要域名，也不要为此改动其他服务的端口策略。"
                    )
                    Text("必须信任 VPS 管理员：两段 SSH 是分段加密，不是绕过 VPS 的端到端加密。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("VPS 怎么准备和配置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func instruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).font(.callout)
        }
    }

    private func command(_ text: String) -> some View {
        Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }
}
