import AppKit
import SwiftUI

struct DashboardScreen: View {
    @ObservedObject var store: AppState
    let url: URL
    @State private var showingChecks = false

    var body: some View {
        DashboardWebView(url: url, dataStoreID: store.sshConfiguration.websiteDataStoreID,
                         onLoadError: { store.banner = $0 })
            .id(store.sshConfiguration.websiteDataStoreID)
            .background(HermlandColor.canvas)
            .overlay(alignment: .top) {
                if let banner = store.banner {
                    Text(banner).font(.callout).foregroundStyle(.red)
                        .padding(10).background(.regularMaterial).padding()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button("连接检查") {
                        showingChecks = true
                        Task { await store.refreshStatus() }
                    }
                    if let status = store.status {
                        HStack(spacing: 6) {
                            StatusDot(ok: true)
                            Text(toolbarTitle(status))
                                .foregroundStyle(HermlandColor.secondary)
                        }
                    }
                    Button("刷新") {
                        NotificationCenter.default.post(name: .hermlandReloadDashboard, object: nil)
                        Task { await store.refreshStatus() }
                    }
                    if store.sshConfiguration.backend == .hermes {
                        Button("在浏览器打开") {
                            Task { await store.openInBrowser() }
                        }
                    }
                    Button("断开") {
                        store.disconnect()
                    }
                    Text("SSH · \(store.sshConfiguration.host)")
                        .font(.caption)
                        .foregroundStyle(HermlandColor.secondary)
                }
            }
            .sheet(isPresented: $showingChecks) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("连接检查与使用指引").font(.title2)
                        Spacer()
                        Button("完成") { showingChecks = false }.keyboardShortcut(.cancelAction)
                    }
                    ConnectionChecksView(diagnostics: store.diagnostics, backend: store.sshConfiguration.backend)
                    Divider()
                    OnboardingActions(store: store, purpose: .additionalDevice)
                }.padding(24).frame(width: 600)
            }
    }

    private func toolbarTitle(_ status: GatewayStatus) -> String {
        if store.sshConfiguration.backend == .openclaw {
            return "OpenClaw · SSH 已连通（Gateway 登录以页面为准）"
        }
        if status.model != "—" {
            return "Hermes · \(status.model)"
        }
        if status.version != "—" {
            return "Hermes \(status.version)"
        }
        return store.settings.displayURL
    }
}

extension Notification.Name {
    static let hermlandReloadDashboard = Notification.Name("hermland.reloadDashboard")
}
