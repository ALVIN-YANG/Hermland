import SwiftUI
import WebKit

struct DashboardWebView: NSViewRepresentable {
    let url: URL
    let dataStoreID: UUID
    var onLoadError: (String?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadError: onLoadError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.attach(view)
        context.coordinator.load(url, in: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.load(url, in: view)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loadedURL: URL?
        private weak var webView: WKWebView?
        private var reloadObserver: NSObjectProtocol?
        private var recoveryTask: Task<Void, Never>?
        private var recoveryAttempts = 0
        private let onLoadError: (String?) -> Void

        init(onLoadError: @escaping (String?) -> Void) {
            self.onLoadError = onLoadError
        }

        func attach(_ view: WKWebView) {
            if webView !== view { loadedURL = nil }
            webView = view
            if reloadObserver == nil {
                reloadObserver = NotificationCenter.default.addObserver(
                    forName: .hermlandReloadDashboard,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self, let view = self.webView, let url = self.loadedURL else { return }
                    self.recoveryTask?.cancel()
                    self.recoveryAttempts = 0
                    self.onLoadError(nil)
                    view.load(URLRequest(url: self.reloadURL(in: view, fallback: url)))
                }
            }
        }

        func load(_ url: URL, in view: WKWebView) {
            if loadedURL == url { return }
            loadedURL = url
            view.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            recoveryTask?.cancel()
            recoveryAttempts = 0
            onLoadError(nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url, let origin = loadedURL else {
                decisionHandler(.cancel)
                return
            }
            if target.scheme == origin.scheme, target.host == origin.host, target.port == origin.port {
                decisionHandler(.allow)
            } else {
                // Upstream external links may open in the browser, never replace our trusted page.
                if navigationAction.navigationType == .linkActivated,
                   ["https", "http"].contains(target.scheme ?? "") {
                    NSWorkspace.shared.open(target)
                }
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // Cancellation is expected when a reload supersedes an earlier navigation.
            if (error as NSError).code == NSURLErrorCancelled { return }
            recoverPage(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            recoverPage(in: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            recoverPage(in: webView)
        }

        private func recoverPage(in view: WKWebView) {
            guard recoveryAttempts < 2, let url = loadedURL else {
                onLoadError("SSH 已连接，但页面加载失败。请点击刷新")
                return
            }
            recoveryAttempts += 1
            recoveryTask?.cancel()
            let retryURL = reloadURL(in: view, fallback: url)
            recoveryTask = Task { @MainActor [weak view] in
                do { try await Task.sleep(nanoseconds: 700_000_000) } catch { return }
                view?.load(URLRequest(url: retryURL))
            }
        }

        private func reloadURL(in view: WKWebView, fallback: URL) -> URL {
            if let current = view.url, current.scheme == fallback.scheme,
               current.host == fallback.host, current.port == fallback.port { return current }
            return fallback
        }

        deinit {
            recoveryTask?.cancel()
            if let reloadObserver {
                NotificationCenter.default.removeObserver(reloadObserver)
            }
        }
    }
}
