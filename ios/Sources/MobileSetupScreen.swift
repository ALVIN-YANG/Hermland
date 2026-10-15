import HermlandCore
import SwiftUI

struct MobileSetupScreen: View {
    @ObservedObject var store: ConnectionStore
    let importAction: () -> Void
    let demoAction: () -> Void
    @State private var showManualGuide = false

    var body: some View {
        VStack(spacing: 0) {
            SetupFlowView(
                backend: $store.backend, deviceName: "这台 iPhone", message: store.error,
                importAction: importAction
            ) { context in
                VStack(alignment: .leading, spacing: 16) {
                    if let key = store.identity {
                        Text("本机公钥指纹").font(SetupTheme.supportFont)
                        Text(key.fingerprint).font(SetupTheme.codeFont).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        DisclosureGroup("查看设备公钥") {
                            Text(key.publicKey).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        }
                    } else {
                        Text("分享时生成本机公钥，私钥留在本机钥匙串。")
                    }
                    Button("分享连接卡") {
                        store.firstSetup = context.firstSetup
                        store.prepareShare(server: context.serverForRequest)
                    }.buttonStyle(SetupPrimaryButtonStyle())
                    Text("在分享面板中复制，再回到原 Agent 对话粘贴发送；这不会自动授权设备。")
                        .font(SetupTheme.supportFont).foregroundStyle(SetupTheme.secondary)
                    Button("Agent 无法执行？查看手动方式") { showManualGuide = true }
                        .buttonStyle(.plain).font(SetupTheme.supportFont).foregroundStyle(SetupTheme.accent)
                }
            } connection: { _ in
                VStack(alignment: .leading, spacing: 20) {
                    SetupHeading(title: "打开收到的连接文件", subtitle: "选择原 Agent 或管理员返回的 JSON，不用自己填写公钥和端口。")
                    Button("导入连接文件", action: importAction).buttonStyle(SetupPrimaryButtonStyle())
                }
            }
            Button("先看离线演示", action: demoAction).font(SetupTheme.supportFont).padding(.bottom, 12)
        }
        .navigationTitle("Hermland").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showManualGuide) { VPSSetupGuide(backendTitle: store.backend.title) }
    }
}
