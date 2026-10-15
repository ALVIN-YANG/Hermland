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
                            .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                .padding(wide ? 44 : 24)
                .frame(
                    maxWidth: 1160, minHeight: geometry.size.height, alignment: page == .welcome ? .center : .topLeading
                )
                .frame(maxWidth: .infinity)
            }
        }
        .background(SetupTheme.canvas(scheme)).foregroundStyle(.primary).tint(SetupTheme.accent)
        .onChange(of: isConnecting) { _, connecting in
            if connecting { page = .connection }
        }
        .sheet(isPresented: $showVPSGuide) {
            VPSSetupGuide(backendTitle: backend.title)
                #if os(macOS)
                    .frame(width: 680, height: 700)
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
                        .font(.callout).foregroundStyle(.secondary).padding(.leading, 14)
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
            VStack(alignment: .leading, spacing: 12) {
                Text("你平时用哪一个？").font(.headline)
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
                }.buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func server(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) {
                SetupHeading(title: "准备一台中转服务器", subtitle: "它在外面和家里之间转接连接，不用搬走你的 Agent。")
                if wide { SetupScene(deviceName: deviceName, showLabels: false).frame(width: 260, height: 135) }
            }
            Text("你有自己的云服务器吗？").font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                choice("我有云服务器", selected: hasServer) { hasServer = true }
                choice("还没有", selected: !hasServer) { hasServer = false }
            }
            if hasServer {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("服务器地址").font(.callout)
                            TextField("你的公网 IP 或域名", text: $context.server.host)
                                .textContentType(.URL)
                                #if os(iOS)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                #endif
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SSH 端口").font(.callout)
                            TextField("22", text: $context.server.port)
                                #if os(iOS)
                                    .keyboardType(.numberPad)
                                #endif
                        }.frame(width: 100)
                    }.textFieldStyle(.roundedBorder).controlSize(.large)
                    Text("需要 Debian / Ubuntu；地址不含账号、密码或 https://。")
                        .font(.callout).foregroundStyle(.secondary)
                    Toggle("我或管理员已核对服务器身份，并能通过 SSH 登录", isOn: $context.server.administratorReady)
                        .toggleStyle(.switch).font(.callout)
                    Button("不会登录？查看服务器准备指引") { showVPSGuide = true }.buttonStyle(.plain)
                        .foregroundStyle(SetupTheme.accent)
                    if context.server.administratorReady && !context.server.isReady {
                        Text("请只填写 IP 或域名；SSH 端口须为 1–65535，不要填写账号、密码或网址。")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }
                Text("下一步让原 Agent 配置中转。这里不会登录服务器，也不会保存管理密码。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("继续，交给我的 Agent") { page = .card }
                    .buttonStyle(SetupPrimaryButtonStyle()).disabled(!context.server.isReady)
                    .frame(maxWidth: wide ? 380 : .infinity)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("先准备好这三项，再回来继续。由你购买和首次登录，App 不代购。")
                    Label("在云服务商控制台创建 Debian / Ubuntu 服务器", systemImage: "1.circle")
                    Label("记下公网 IP 和 SSH 端口，不用购买域名", systemImage: "2.circle")
                    Label("用控制台或可信 SSH 核对身份，确认自己能管理它", systemImage: "3.circle")
                    Button("查看详细准备指引") { showVPSGuide = true }
                    Button("服务器准备好了，填写地址") { hasServer = true }
                        .buttonStyle(SetupPrimaryButtonStyle()).frame(maxWidth: wide ? 380 : .infinity)
                }.font(.body)
            }
            Button("其他设备已经能用 Hermland？只添加\(deviceName)") {
                context.firstSetup = false
                page = .card
            }.buttonStyle(.plain).font(.callout).foregroundStyle(SetupTheme.accent)
        }
    }

    private func handoff(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            SetupHeading(
                title: "把配置交给家里的 \(backend.title)",
                subtitle: "回到你平时使用的 \(backend.title) 对话，粘贴发送这张连接卡。")
            HStack(alignment: .center, spacing: 36) {
                VStack(alignment: .leading, spacing: 18) {
                    Label("\(deviceName) 的连接卡", systemImage: "doc.text").font(.title3.weight(.semibold))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("复用我现有的 \(backend.title)")
                        Text(context.firstSetup ? "配置我的中转服务器" : "只添加这台设备，不重新部署")
                        Text("授权 \(deviceName) 前，先让我确认")
                    }.foregroundStyle(.secondary)
                    cardActions(context)
                    Button("我收到连接文件了", action: importAction)
                        .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                }
                .padding(wide ? 26 : 20).frame(maxWidth: .infinity, alignment: .leading)
                .background(SetupTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.06)))
                if wide { SetupScene(deviceName: deviceName, showLabels: false).frame(width: 320) }
            }
            Label("对方提出授权时，核对设备名和公钥指纹，再在原对话确认。", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").foregroundStyle(SetupTheme.accent)
                Text(title).font(.body.weight(.medium))
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
