import SwiftUI
import WebKit
import HermlandCore

struct AgentPage: View {
    @ObservedObject var store: ConnectionStore
    @StateObject private var browser = AgentBrowser()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MessengerIcon(size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.configuration?.backend.title ?? "Agent").font(.headline)
                    Label(store.connected ? "已连接" : "未连接", systemImage: store.connected ? "checkmark.circle.fill" : "link")
                        .font(.caption).foregroundStyle(store.connected ? Palette.accent : .secondary)
                }
                Spacer()
                Button { store.tab = 1 } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                    .accessibilityLabel("连接详情")
            }.padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
            ZStack {
                if let web = browser.webView { EmbeddedAgent(webView: web) }
                if !store.connected {
                    ContentUnavailableView {
                        Label(store.connecting ? "正在恢复连接" : "尚未连接", systemImage: "link")
                    } description: {
                        Text("连接恢复后继续原会话。不会自动重发消息。")
                    } actions: {
                        Button("查看连接") { store.tab = 1 }.buttonStyle(.borderedProminent)
                    }.background(Palette.canvas)
                }
            }
            if let message = browser.error, store.connected {
                VStack(spacing: 8) {
                    Text(message).font(.callout)
                    Button("重新打开页面") { browser.openCurrentPage() }
                }.padding().frame(maxWidth: .infinity).background(Palette.canvas)
            }
        }
        .onChange(of: store.pageGeneration, initial: true) { _, _ in
            if store.connected, let config = store.configuration { browser.connect(config, generation: store.pageGeneration) }
        }
        .onChange(of: store.connected) { _, connected in browser.webView?.isUserInteractionEnabled = connected }
    }
}

struct EmbeddedAgent: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Retains only safe navigation state. Recovery always performs a GET, never reloads a POST.
@MainActor
final class AgentBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var webView: WKWebView?
    @Published private(set) var error: String?
    private var route: SSHConfiguration?
    private var generation: UUID?
    private var safeURL: URL?

    func connect(_ config: SSHConfiguration, generation: UUID) {
        guard self.generation != generation else { return }
        self.generation = generation
        if route?.websiteDataStoreID != config.websiteDataStoreID || webView == nil {
            webView?.stopLoading()
            let settings = WKWebViewConfiguration()
            settings.websiteDataStore = WKWebsiteDataStore(forIdentifier: config.websiteDataStoreID)
            let web = WKWebView(frame: .zero, configuration: settings)
            web.navigationDelegate = self
            web.uiDelegate = self
            web.allowsBackForwardNavigationGestures = true
            web.isInspectable = false
            webView = web
            safeURL = config.localURL
        }
        route = config
        webView?.isUserInteractionEnabled = true
        openCurrentPage()
    }

    func openCurrentPage() {
        guard let route else { return }
        error = nil
        let target = safeURL.flatMap { sameOrigin($0, route.localURL) ? $0 : nil } ?? route.localURL
        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        webView?.load(request)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let route else { decisionHandler(.cancel); return }
        if sameOrigin(url, route.localURL) {
            if navigationAction.targetFrame?.isMainFrame == true,
               (navigationAction.request.httpMethod ?? "GET") == "GET" { safeURL = url }
            decisionHandler(.allow)
        } else {
            if navigationAction.navigationType == .linkActivated, url.scheme == "https" {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { error = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { self.error = "原网页暂时无法打开。先检查连接，再重试页面。" }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.error = "页面加载中断，请检查原会话状态后重试。"
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        error = "网页进程已结束。重新打开页面不会重发消息。"
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
    func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme == rhs.scheme && lhs.host == rhs.host && lhs.port == rhs.port
    }
}
