import Foundation

/// Read-only liveness. WebKit, not this probe, owns backend authentication and chat.
public enum BackendProbe {
    public static func check(_ configuration: SSHConfiguration) async throws {
        let config = try configuration.validated()
        let settings = URLSessionConfiguration.ephemeral
        settings.connectionProxyDictionary = [:]
        settings.httpShouldSetCookies = false
        settings.timeoutIntervalForRequest = 8
        settings.timeoutIntervalForResource = 12
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: settings, delegate: LocalRedirect(origin: config.localURL), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var parts = URLComponents(url: config.localURL, resolvingAgainstBaseURL: false)!
        parts.path = config.backend.healthPath
        let (data, response) = try await session.data(from: parts.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 65_536,
              let health = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SSHConnectionError.process("Agent 健康检查失败。请核对后端类型与原服务状态。")
        }
        let healthy = config.backend == .hermes
            ? health["status"] as? String == "ok"
            : health["status"] as? String == "live" && health["ok"] as? Bool == true
        guard healthy else { throw SSHConnectionError.process("响应不是所选 Agent 的健康状态。") }
        let (page, uiResponse) = try await session.data(from: config.localURL)
        guard (uiResponse as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: page, encoding: .utf8),
              config.backend == .hermes ? html.lowercased().contains("hermes") : html.contains("<openclaw-app") else {
            throw SSHConnectionError.process("Agent 可达，但网页未通过检查。请核对界面路径与原网页登录要求。")
        }
    }

    // A password-protected Hermes redirects to its login page. Do not follow
    // redirects outside this exact local origin, even to another loopback port.
    private final class LocalRedirect: NSObject, URLSessionTaskDelegate {
        let origin: URL
        private var redirects = 0
        init(origin: URL) { self.origin = origin }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            guard redirects < 3, request.httpMethod == "GET", let target = request.url,
                  target.scheme == origin.scheme, target.host == origin.host, target.port == origin.port,
                  target.user == nil, target.password == nil else { completionHandler(nil); return }
            redirects += 1
            completionHandler(request)
        }
    }
}
