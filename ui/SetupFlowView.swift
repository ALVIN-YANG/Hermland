import SwiftUI

#if os(iOS)
    import HermlandCore
#endif

enum SetupPage: Equatable { case welcome, server, card, connection }

/// Presentation only. Installation, approval and connection stay in the existing platform stores.
struct SetupFlowView<CardActions: View, Connection: View>: View {
    @Binding var backend: AgentBackend
    let deviceName: String
    let message: String?
    let isConnecting: Bool
    let importAction: () -> Void
    let cardActions: (SetupContext) -> CardActions
    let connection: (Bool) -> Connection
    @State private var page: SetupPage
    @State private var context = SetupContext()
    @State private var hasServer = true
    @State private var showVPSGuide = false
    @State private var showPrinciples = false
    @Environment(\.colorScheme) private var scheme

    init(
        backend: Binding<AgentBackend>, deviceName: String, initialPage: SetupPage = .welcome,
        message: String?, isConnecting: Bool = false, importAction: @escaping () -> Void,
        @ViewBuilder cardActions: @escaping (SetupContext) -> CardActions,
        @ViewBuilder connection: @escaping (Bool) -> Connection
    ) {
        _backend = backend
        self.deviceName = deviceName
        self.message = message
        self.isConnecting = isConnecting
        self.importAction = importAction
        self.cardActions = cardActions
        self.connection = connection
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 850
            ScrollView {
                VStack(alignment: .leading, spacing: wide ? 32 : 24) {
                    navigation
                    if page == .welcome {
                        welcome(wide: wide).frame(maxHeight: .infinity)
                    } else if page == .server {
                        server(wide: wide)
                    } else if page == .card {
                        handoff(wide: wide)
                    } else {
                        connection(wide)
                    }
                    if let message {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(SetupTheme.supportFont).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                .padding(wide ? 44 : 24)
                .frame(
                    maxWidth: 1160, minHeight: geometry.size.height, alignment: page == .welcome ? .center : .topLeading
                )
                .frame(maxWidth: .infinity)
            }
        }
        .font(SetupTheme.bodyFont)
        .background(SetupTheme.canvas(scheme)).foregroundStyle(.primary).tint(SetupTheme.accent)
        .onChange(of: isConnecting) { _, connecting in
            if connecting { page = .connection }
        }
        .sheet(isPresented: $showVPSGuide) {
            VPSSetupGuide(backendTitle: backend.title)
                #if os(macOS)
                    .frame(width: 760, height: 760)
                #endif
        }
        .sheet(isPresented: $showPrinciples) {
            ConnectionPrinciplesView()
                #if os(macOS)
                    .frame(width: 680, height: 700)
                #endif
        }
    }

    private var navigation: some View {
        HStack {
            if page != .welcome {
                Button {
                    goBack()
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.plain).foregroundStyle(SetupTheme.accent)
                if page != .connection {
                    Text(context.firstSetup ? "首次连接 · \(page == .server ? 1 : 2)/3" : "新增这台设备")
                        .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary).padding(.leading, 14)
                }
            }
            Spacer()
            Button {
                showPrinciples = true
            } label: {
                Label("连接原理", systemImage: "questionmark.circle")
            }
            .buttonStyle(.plain).foregroundStyle(SetupTheme.accent)
        }.frame(minHeight: 24)
    }

    private func welcome(wide: Bool) -> some View {
        Group {
            if wide {
                HStack(spacing: 36) {
                    welcomeActions.frame(maxWidth: .infinity)
                    SetupScene(deviceName: deviceName).frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    SetupScene(deviceName: deviceName).frame(maxHeight: 215)
                    welcomeActions
                }
            }
        }.padding(.vertical, wide ? 60 : 4)
    }

    private var welcomeActions: some View {
        VStack(alignment: .leading, spacing: 28) {
            SetupHeading(title: "家里的 Agent，\n出门也能用", subtitle: "连接你已有的 Agent，原来的记忆和会话都在。")
            Text("家里的 Mac 运行 Agent，你的云服务器转接，\(deviceName) 打开使用。")
                .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Text("你平时用哪一个？").font(SetupTheme.labelFont)
                HStack(spacing: 12) {
                    ForEach(AgentBackend.allCases) { option in
                        choice(option.title, selected: backend == option) { backend = option }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                Button("开始连接") {
                    context.firstSetup = true
                    page = .server
                }
                .buttonStyle(SetupPrimaryButtonStyle())
                Button("已有连接文件？直接导入", action: importAction).buttonStyle(.plain)
                    .foregroundStyle(SetupTheme.accent)
                Button("其他设备已连好？新增\(deviceName)") {
                    context.firstSetup = false
                    page = .card
                }.buttonStyle(.plain).font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
            }
        }
    }

    private func server(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 24) {
                SetupHeading(title: "准备一台中转服务器", subtitle: "VPS 就是你租用的云服务器，只转接连接。Agent 仍在家里的 Mac。")
                if wide { SetupScene(deviceName: deviceName, showLabels: false).frame(width: 260, height: 112) }
            }
            Text("你有自己的云服务器吗？").font(SetupTheme.labelFont)
            HStack(spacing: 12) {
                choice("我有云服务器", selected: hasServer) { hasServer = true }
                choice("还没有", selected: !hasServer) { hasServer = false }
            }.frame(maxWidth: 560)
            if hasServer {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("服务器地址").font(SetupTheme.supportFont)
                            TextField("你的公网 IP 或域名", text: $context.server.host)
                                .textContentType(.URL)
                                #if os(iOS)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                #endif
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SSH 端口").font(SetupTheme.supportFont)
                            TextField("22", text: $context.server.port)
                                #if os(iOS)
                                    .keyboardType(.numberPad)
                                #endif
                        }.frame(width: 128)
                    }.textFieldStyle(SetupTextFieldStyle()).frame(maxWidth: 560)
                    Text("使用 Debian / Ubuntu。填公网 IP，不填家里的局域网地址；不用购买域名。")
                        .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
                    Toggle("我或管理员已核对身份，并成功通过 SSH 登录这台服务器", isOn: $context.server.administratorReady)
                        .toggleStyle(.switch).font(SetupTheme.supportFont)
                    Button("不知道 IP、端口或怎么登录？查看准备步骤") { showVPSGuide = true }.buttonStyle(.plain)
                        .foregroundStyle(SetupTheme.accent)
                    if context.server.administratorReady && !context.server.isReady {
                        Text("请只填写 IP 或域名；SSH 端口须为 1–65535，不要填写账号、密码或网址。")
                            .font(SetupTheme.supportFont).foregroundStyle(.orange)
                    }
                }
                Text("填好地址后，再让原 Agent 协助配置。这里不会登录服务器、安装软件或授权设备，也不收管理员密码。")
                    .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
                Button("继续，交给我的 Agent") { page = .card }
                    .buttonStyle(SetupPrimaryButtonStyle()).disabled(!context.server.isReady)
                    .frame(maxWidth: wide ? 380 : .infinity)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("先完成下面三件事，再回这里填写。已有合适服务器就复用；费用由你支付给云厂商。")
                    SetupInstructionRow(number: "1", title: "创建或复用服务器", detail: "在你信任的云厂商选择 Debian / Ubuntu，不用把 Agent 搬过去。")
                    SetupInstructionRow(number: "2", title: "记下公网 IP 和 SSH 端口", detail: "在云厂商控制台查看。SSH 端口通常是 22，不需要域名。")
                    SetupInstructionRow(number: "3", title: "核对身份，确认能管理", detail: "你或可信管理员先成功通过 SSH 登录；不熟悉就按准备指南操作。")
                    Button("跟着准备服务器") { showVPSGuide = true }.buttonStyle(SetupSecondaryButtonStyle())
                    Button("服务器准备好了，填写地址") { hasServer = true }
                        .buttonStyle(SetupPrimaryButtonStyle()).frame(maxWidth: wide ? 380 : .infinity)
                }.font(SetupTheme.bodyFont)
            }
            Button("其他设备已经能用 Hermland？只添加\(deviceName)") {
                context.firstSetup = false
                page = .card
            }.buttonStyle(.plain).font(SetupTheme.supportFont).foregroundStyle(SetupTheme.accent)
        }
    }

    private func handoff(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            SetupHeading(
                title: "把配置交给家里的 \(backend.title)",
                subtitle: "连接卡是一段已写好的配置指令，附上本机公钥。复制后，还需要你亲自发出去。")
            if wide {
                HStack(alignment: .top, spacing: 36) {
                    connectionCard.frame(maxWidth: 560)
                    handoffSteps.frame(maxWidth: 400)
                }
            } else {
                connectionCard
                handoffSteps
            }
            VStack(alignment: .leading, spacing: 12) {
                Button("我收到连接文件了", action: importAction)
                    .buttonStyle(SetupSecondaryButtonStyle())
                Text("先把对方返回的 .json 文件保存到\(deviceName)，再点这里选择。文件名可以不同，不用自己编写配置。")
                    .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
            }
            Text("Agent 有执行权限时可以协助配置；没有权限，就由你或管理员按手动方式执行。复制、发送和授权是三件不同的事。")
                .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("\(deviceName) 的连接卡", systemImage: "doc.text").font(SetupTheme.labelFont)
            Text(context.firstSetup ? "复用我已有的 \(backend.title)，配置中转；先让我确认，再授权这台设备。" : "只添加这台设备，不重装 Agent，也不重新部署服务器。")
                .foregroundStyle(SetupTheme.secondary)
            cardActions(context)
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(SetupTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.06)))
    }

    private var handoffSteps: some View {
        VStack(alignment: .leading, spacing: 24) {
            SetupInstructionRow(number: "1", title: "回原对话，粘贴发送", detail: "用你平时与家里 \(backend.title) 聊天的入口，不是在 Hermland 里发送。")
            SetupInstructionRow(number: "2", title: "对照指纹，再同意授权", detail: "指纹是 SHA256:… 识别码。对方报告的本机指纹，应与连接卡一致；首次还要核对家里 Mac 的公钥。")
            SetupInstructionRow(number: "3", title: "收回 .json 连接文件", detail: "让 Agent 或管理员返回可保存的文件，不是截图或公钥。导入检查后，再登录原网页、发消息确认回答。")
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").foregroundStyle(SetupTheme.accent)
                Text(title).font(SetupTheme.bodyFont.weight(.medium))
                Spacer(minLength: 0)
            }.padding(16).frame(maxWidth: .infinity, minHeight: 24)
                .background(
                    selected ? SetupTheme.accent.opacity(0.08) : SetupTheme.surface(scheme),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(selected ? SetupTheme.accent : .primary.opacity(0.12))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func goBack() {
        switch page {
        case .welcome: break
        case .server: page = .welcome
        case .card: page = context.firstSetup ? .server : .welcome
        case .connection: page = .welcome
        }
    }
}
